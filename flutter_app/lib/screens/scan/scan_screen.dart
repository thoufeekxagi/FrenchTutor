import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/storage_service.dart';
import '../../design/tokens.dart';
import '../../models/session.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/pdf_page_renderer.dart';
import '../../services/vision_scan_service.dart';
import '../../utils/transcript_filter.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/inline_call_bar.dart';
import 'camera_capture_screen.dart';

enum _ScanMessageRole { user, assistant }

enum _AttachmentSource { camera, gallery, pdf }

class _ScanMessage {
  _ScanMessage({
    required this.id,
    required this.role,
    this.text = '',
    this.imageBytes,
    this.isLoading = false,
    this.attachmentSummary,
  });

  final String id;
  final _ScanMessageRole role;
  final String text;
  final Uint8List? imageBytes;
  bool isLoading;
  String? attachmentSummary;

  bool get isUser => role == _ScanMessageRole.user;
  bool get hasAttachment => imageBytes != null || attachmentSummary != null;
}

class _ScanSession {
  _ScanSession({required this.id, required this.startedAt});

  final String id;
  final DateTime startedAt;
  final List<_ScanMessage> messages = [];
  DateTime? closedAt;
  bool hadCall = false;

  bool get isClosed => closedAt != null;

  String get label {
    for (final message in messages) {
      if (!message.isUser && message.text.trim().isNotEmpty) {
        final firstLine = message.text.trim().split('\n').first.trim();
        return firstLine.length <= 42
            ? firstLine
            : '${firstLine.substring(0, 39)}…';
      }
    }
    for (final message in messages) {
      final summary = message.attachmentSummary?.trim();
      if (summary != null && summary.isNotEmpty) {
        final firstLine = summary.split('\n').first.trim();
        if (firstLine.isNotEmpty) {
          return firstLine.length <= 42
              ? firstLine
              : '${firstLine.substring(0, 39)}…';
        }
      }
    }
    return messages.isEmpty ? 'New photo session' : 'Photo tutor session';
  }

  String get context {
    final lines = <String>[];
    for (final message in messages) {
      if (message.hasAttachment) {
        final summary = message.attachmentSummary;
        lines.add(
          summary == null || summary.isEmpty
              ? 'Student uploaded a photo.'
              : 'Student uploaded a photo. Image summary: $summary',
        );
      } else if (message.text.trim().isNotEmpty) {
        lines.add(
          '${message.isUser ? 'Student' : ActiveTutor.current.displayName}: ${message.text.trim()}',
        );
      }
    }
    final value = lines.join('\n');
    return value.length <= 6000 ? value : value.substring(value.length - 6000);
  }

  List<Map<String, String>> get conversation {
    final turns = <Map<String, String>>[];
    for (final message in messages) {
      final content = message.hasAttachment
          ? 'The student uploaded a photo. Image summary: ${message.attachmentSummary ?? 'not available yet'}'
          : message.text.trim();
      if (content.isEmpty) continue;
      turns.add({
        'role': message.isUser ? 'user' : 'assistant',
        'content': content,
      });
    }
    return turns.length <= 30 ? turns : turns.sublist(turns.length - 30);
  }
}

/// Live Vision Scan — the "point the camera at a sign and get one quiet
/// answer" tab. Default mode is a silent, single-shot chat: capture/pick an
/// image or PDF, get one concise reply per image, no open-ended back-and-
/// forth. The "Call" button escalates to a live voice session (reusing
/// [InlineCallController] exactly like every other lab screen), and further
/// photos taken while that call is live get merged and injected into the
/// SAME session via `injectContext` instead of starting a new call.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver {
  final _sessions = <_ScanSession>[];
  final _scanService = VisionScanService();
  final _pdfRenderer = PdfPageRenderer();
  final _picker = ImagePicker();
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();

  late final InlineCallController _call;
  late final StorageService _storage;
  late final LessonAgentService _agent;

  _ScanSession? _activeSession;
  _ScanSession? _callSession;
  Future<void> _pipeline = Future.value();
  bool _chatSending = false;

  @override
  void initState() {
    super.initState();
    _storage = ref.read(storageServiceProvider);
    _agent = ref.read(lessonAgentServiceProvider);
    _restoreSavedSessions();
    WidgetsBinding.instance.addObserver(this);
    _call = InlineCallController(
      sessionType: LiveSessionType.visionScan,
      lessonContext: () => _latestContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (!mounted) return;
        if (_call.isLive) {
          _activeSession?.hadCall = true;
          _callSession ??= _activeSession;
        } else if (!_call.connecting) {
          _callSession = null;
        }
        setState(() {});
      },
      onUserTranscript: _handleCallUserTranscript,
      onTutorTranscript: _handleCallTutorTranscript,
    );
  }

  void _restoreSavedSessions() {
    final saved = _storage
        .getAllSessions()
        .where((session) => session.stage == 'vision_scan')
        .toList(growable: false);
    for (final savedSession in saved.reversed) {
      final startedAt = DateTime.tryParse(savedSession.startedAt);
      if (startedAt == null) continue;
      final session = _ScanSession(id: savedSession.id, startedAt: startedAt);
      final endedAt = savedSession.endedAt == null
          ? null
          : DateTime.tryParse(savedSession.endedAt!);
      session.closedAt = endedAt;
      for (final message in _storage.getSessionMessages(
        sessionId: savedSession.id,
      )) {
        if (message.content == '[Photo uploaded]') {
          session.messages.add(
            _ScanMessage(
              id: message.id,
              role: _ScanMessageRole.user,
              attachmentSummary: 'Photo from this session',
            ),
          );
        } else if (message.content.trim().isNotEmpty) {
          session.messages.add(
            _ScanMessage(
              id: message.id,
              role: message.isUser
                  ? _ScanMessageRole.user
                  : _ScanMessageRole.assistant,
              text: message.content,
            ),
          );
        }
      }
      _sessions.add(session);
      if (!session.isClosed && _activeSession == null) {
        _activeSession = session;
      }
    }
  }

  String get _latestContext {
    final session = _ensureSession();
    _callSession = session;
    final context = session.context;
    return context.isEmpty
        ? 'The student just opened the camera scan feature and started a live call without sending a photo yet.'
        : context;
  }

  _ScanSession _ensureSession() {
    final current = _activeSession;
    if (current != null && !current.isClosed) return current;
    final session = _ScanSession(
      id: const Uuid().v4(),
      startedAt: DateTime.now(),
    );
    _sessions.add(session);
    _activeSession = session;
    return session;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final session = _activeSession;
      if (session != null && session.messages.isNotEmpty) {
        _persistSession(session);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerController.dispose();
    _scrollController.dispose();
    _call.dispose();
    _scanService.dispose();
    super.dispose();
  }

  void _handleImage(Uint8List bytes) {
    final session = _ensureSession();
    final message = _ScanMessage(
      id: const Uuid().v4(),
      role: _ScanMessageRole.user,
      imageBytes: bytes,
      isLoading: true,
    );
    setState(() => session.messages.add(message));
    _scrollToLatest();
    _storage.saveMessage(
      sessionId: session.id,
      role: 'user',
      content: '[Photo uploaded]',
    );
    _persistSession(session);
    _pipeline = _pipeline.then((_) => _processImage(session, message));
  }

  Future<void> _processImage(_ScanSession session, _ScanMessage message) async {
    try {
      final result = await _scanService.scan(
        imageBytes: message.imageBytes!,
        conversationContext: session.context,
      );
      if (result.reply.trim().isEmpty) {
        throw StateError('The vision model returned an empty response.');
      }
      final reply = result.reply.trim();
      message.isLoading = false;
      if (_call.isLive &&
          identical(_activeSession, session) &&
          _call.gemini?.isConnected == true) {
        message.attachmentSummary = reply;
        _call.gemini?.injectContext(
          'The student just added a new photo. Image understanding: $reply',
          expectReply: true,
        );
      } else {
        _appendMessage(
          session,
          _ScanMessage(
            id: const Uuid().v4(),
            role: _ScanMessageRole.assistant,
            text: reply,
          ),
        );
      }
    } catch (error) {
      message.isLoading = false;
      _appendMessage(
        session,
        _ScanMessage(
          id: const Uuid().v4(),
          role: _ScanMessageRole.assistant,
          text: _scanErrorText(error),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: DesignTokens.durationFast,
        curve: DesignTokens.curveStandard,
      );
    });
  }

  void _appendMessage(_ScanSession session, _ScanMessage message) {
    session.messages.add(message);
    _scrollToLatest();
    if (message.text.trim().isNotEmpty) {
      _storage.saveMessage(
        sessionId: session.id,
        role: message.isUser ? 'user' : 'assistant',
        content: message.text.trim(),
      );
    }
    _persistSession(session);
  }

  String _scanErrorText(Object error) {
    if (error is AgentError) return 'Scan failed: ${error.message}';
    return 'Scan failed: $error';
  }

  void _persistSession(_ScanSession session) {
    _storage.saveSession(
      Session(
        id: session.id,
        startedAt: session.startedAt.toIso8601String(),
        endedAt: session.closedAt?.toIso8601String(),
        summary: session.label,
        topic: 'Photo tutor',
        stage: 'vision_scan',
      ),
    );
  }

  void _handleCallUserTranscript(String text) {
    if (!isFrenchEnglishTranscript(text)) return;
    final session = _callSession ?? _ensureSession();
    _appendMessage(
      session,
      _ScanMessage(
        id: const Uuid().v4(),
        role: _ScanMessageRole.user,
        text: text,
      ),
    );
    if (mounted) setState(() {});
  }

  void _handleCallTutorTranscript(String text) {
    final session = _callSession ?? _ensureSession();
    _appendMessage(
      session,
      _ScanMessage(
        id: const Uuid().v4(),
        role: _ScanMessageRole.assistant,
        text: text,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _sendChat() async {
    final question = _composerController.text.trim();
    if (question.isEmpty || _chatSending) return;
    final session = _ensureSession();
    final history = session.conversation;
    _composerController.clear();
    _appendMessage(
      session,
      _ScanMessage(
        id: const Uuid().v4(),
        role: _ScanMessageRole.user,
        text: question,
      ),
    );
    if (mounted) setState(() {});

    if (_call.active) {
      _call.sendText(question);
      return;
    }

    setState(() => _chatSending = true);
    try {
      final reply = await _agent.answerVisionScanChat(
        question: question,
        conversation: history,
      );
      if (reply.trim().isEmpty) {
        throw StateError('The text model returned an empty response.');
      }
      _appendMessage(
        session,
        _ScanMessage(
          id: const Uuid().v4(),
          role: _ScanMessageRole.assistant,
          text: reply.trim(),
        ),
      );
    } catch (error) {
      _appendMessage(
        session,
        _ScanMessage(
          id: const Uuid().v4(),
          role: _ScanMessageRole.assistant,
          text: _scanErrorText(error),
        ),
      );
    }
    if (mounted) setState(() => _chatSending = false);
  }

  Future<void> _showAttachmentOptions() async {
    final choice = await showPSActionSheet<_AttachmentSource>(
      context,
      title: 'Add to this session',
      actions: const [
        (
          label: 'Take a photo',
          value: _AttachmentSource.camera,
          destructive: false,
        ),
        (
          label: 'Choose from Photos',
          value: _AttachmentSource.gallery,
          destructive: false,
        ),
        (
          label: 'Import a PDF',
          value: _AttachmentSource.pdf,
          destructive: false,
        ),
      ],
    );
    switch (choice) {
      case _AttachmentSource.camera:
        await _captureFromCamera();
      case _AttachmentSource.gallery:
        await _pickFromGallery();
      case _AttachmentSource.pdf:
        await _pickPdf();
      case null:
        break;
    }
  }

  Future<void> _captureFromCamera() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      CupertinoPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (bytes != null && mounted) _handleImage(bytes);
  }

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final imageBytes = await file.readAsBytes();
    if (mounted) _handleImage(imageBytes);
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final pages = await _pdfRenderer.renderPages(bytes);
    if (!mounted) return;
    for (final page in pages) {
      _handleImage(page);
    }
  }

  Future<void> _showSessionPicker() async {
    final choice = await showDialog<int>(
      context: context,
      barrierColor: DesignTokens.ink.withValues(alpha: 0.28),
      builder: (context) => _ScanSessionPickerDialog(
        sessions: _sessions,
        activeIndex: _activeSession == null
            ? -1
            : _sessions.indexOf(_activeSession!),
      ),
    );
    if (choice == null) return;
    if (choice == -1) {
      await _startNewSession();
    } else if (choice !=
        (_activeSession == null ? -2 : _sessions.indexOf(_activeSession!))) {
      if (_call.isLive) await _call.end();
      await _closeActiveSession();
      if (mounted) setState(() => _activeSession = _sessions[choice]);
    }
  }

  Future<void> _showNewSessionDialog() async {
    final shouldStart = await showDialog<bool>(
      context: context,
      barrierColor: DesignTokens.ink.withValues(alpha: 0.28),
      builder: (context) => const _NewScanSessionDialog(),
    );
    if (shouldStart == true) await _startNewSession();
  }

  Future<void> _startNewSession() async {
    await _closeActiveSession();
    final session = _ScanSession(
      id: const Uuid().v4(),
      startedAt: DateTime.now(),
    );
    _sessions.add(session);
    if (mounted) setState(() => _activeSession = session);
  }

  Future<void> _closeActiveSession() async {
    if (_call.isLive) await _call.end();
    final session = _activeSession;
    if (session == null || session.isClosed) return;
    session.closedAt = DateTime.now();
    _persistSession(session);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = _activeSession;
    final canCompose = session == null || !session.isClosed;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Photo tutor', style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: _ScanHeaderButton(
          icon: CupertinoIcons.square_pencil,
          label: 'Start a new photo tutor session',
          onPressed: _showNewSessionDialog,
        ),
        actions: [
          _ScanHeaderButton(
            icon: CupertinoIcons.clock,
            label: 'Photo tutor sessions',
            onPressed: _showSessionPicker,
          ),
          InlineCallActions(controller: _call),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_call.isLive || _call.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: InlineCallStatusCard(
                  controller: _call,
                  showLastTutorLine: false,
                  listeningLabel:
                      'On the call. Photos and chat stay in this session.',
                ),
              ),
            Expanded(
              child: session == null || session.messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      physics: const BouncingScrollPhysics(),
                      itemCount: session.messages.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ScanMessageBubble(message: session.messages[i]),
                      ),
                    ),
            ),
            _ScanComposer(
              controller: _composerController,
              enabled: canCompose,
              sending: _chatSending,
              onAttach: _showAttachmentOptions,
              onSend: _sendChat,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.camera_on_rectangle,
              size: 40,
              color: DesignTokens.mutedDim,
            ),
            const SizedBox(height: 12),
            Text(
              'Add a sign, menu, or document, then ask anything about it.',
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanMessageBubble extends StatelessWidget {
  const _ScanMessageBubble({required this.message});

  final _ScanMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: user ? DesignTokens.primarySoft : DesignTokens.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(user ? 16 : 4),
            bottomRight: Radius.circular(user ? 4 : 16),
          ),
          border: user ? null : Border.all(color: DesignTokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 224,
                  height: 168,
                  child: Image.memory(message.imageBytes!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (message.isLoading)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PSProgressIndicator(),
                  const SizedBox(width: 8),
                  Text(
                    'Reading…',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            if (message.text.trim().isNotEmpty)
              Text(
                message.text,
                style: DesignTokens.body(15).copyWith(height: 1.4),
              ),
            if (message.attachmentSummary != null) ...[
              if (message.text.trim().isNotEmpty || message.imageBytes != null)
                const SizedBox(height: 8),
              Text(
                message.attachmentSummary!,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewScanSessionDialog extends StatelessWidget {
  const _NewScanSessionDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                CupertinoIcons.square_pencil,
                color: DesignTokens.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 20),
            Text('Start a new session', style: DesignTokens.display(22)),
            const SizedBox(height: 8),
            Text(
              'Begin a fresh photo chat. Your previous scans will stay in your session history.',
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            _ScanDialogButton(
              label: 'Start new session',
              icon: CupertinoIcons.arrow_right,
              primary: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            _ScanDialogButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSessionPickerDialog extends StatelessWidget {
  const _ScanSessionPickerDialog({
    required this.sessions,
    required this.activeIndex,
  });

  final List<_ScanSession> sessions;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: DesignTokens.canvasDim,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      CupertinoIcons.clock,
                      color: DesignTokens.inkSoft,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Previous sessions',
                          style: DesignTokens.display(19),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Return to a scan or start fresh.',
                          style: DesignTokens.body(
                            12,
                          ).copyWith(color: DesignTokens.mutedDim),
                        ),
                      ],
                    ),
                  ),
                  _ScanDialogCloseButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: sessions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'No previous photo sessions yet.',
                          style: DesignTokens.body(
                            14,
                          ).copyWith(color: DesignTokens.muted),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final isActive = index == activeIndex;
                          return _ScanSessionRow(
                            session: session,
                            isActive: isActive,
                            onPressed: () => Navigator.of(context).pop(index),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              _ScanDialogButton(
                label: 'Start a new session',
                icon: CupertinoIcons.square_pencil,
                primary: true,
                onPressed: () => Navigator.of(context).pop(-1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanSessionRow extends StatelessWidget {
  const _ScanSessionRow({
    required this.session,
    required this.isActive,
    required this.onPressed,
  });

  final _ScanSession session;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final status = isActive
        ? 'Current session'
        : session.isClosed
        ? 'Closed'
        : 'Open';
    return Semantics(
      button: true,
      label: '${session.label}, $status',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isActive ? DesignTokens.primarySoft : DesignTokens.canvasDim,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? DesignTokens.primary : DesignTokens.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.body(14, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        style: DesignTokens.body(11).copyWith(
                          color: isActive
                              ? DesignTokens.primary
                              : DesignTokens.mutedDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: isActive ? DesignTokens.primary : DesignTokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanDialogButton extends StatelessWidget {
  const _ScanDialogButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: primary ? DesignTokens.primary : DesignTokens.canvasDim,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: DesignTokens.body(14, weight: FontWeight.w700).copyWith(
                  color: primary ? Colors.white : DesignTokens.inkSoft,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(
                  icon,
                  size: 18,
                  color: primary ? Colors.white : DesignTokens.inkSoft,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanDialogCloseButton extends StatelessWidget {
  const _ScanDialogCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            CupertinoIcons.xmark,
            size: 18,
            color: DesignTokens.muted,
          ),
        ),
      ),
    );
  }
}

class _ScanComposer extends StatelessWidget {
  const _ScanComposer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onAttach,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        border: Border(top: BorderSide(color: DesignTokens.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ComposerIconButton(
                icon: CupertinoIcons.paperclip,
                label: 'Add a photo or PDF',
                onPressed: enabled ? onAttach : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  placeholder: enabled
                      ? 'Ask about this scan…'
                      : 'Session closed',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: DesignTokens.canvasDim,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  style: DesignTokens.body(15),
                  placeholderStyle: DesignTokens.body(
                    15,
                  ).copyWith(color: DesignTokens.mutedDim),
                  onSubmitted: (_) {
                    if (enabled) onSend();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _ComposerIconButton(
                icon: sending
                    ? CupertinoIcons.arrow_2_circlepath
                    : CupertinoIcons.arrow_up,
                label: 'Send question',
                onPressed: enabled && !sending ? onSend : null,
                filled: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanHeaderButton extends StatelessWidget {
  const _ScanHeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(icon, size: 21, color: DesignTokens.inkSoft),
          ),
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final active = onPressed != null;
    return Semantics(
      button: true,
      enabled: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (active ? DesignTokens.primary : DesignTokens.canvasDim)
                  : DesignTokens.canvasDim,
            ),
            child: Center(child: sendingIcon(icon, active, filled)),
          ),
        ),
      ),
    );
  }

  Widget sendingIcon(IconData icon, bool active, bool filled) {
    return Icon(
      icon,
      size: 20,
      color: filled && active ? Colors.white : DesignTokens.inkSoft,
    );
  }
}
