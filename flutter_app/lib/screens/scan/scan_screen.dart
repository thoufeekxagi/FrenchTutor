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
  });

  final String id;
  final _ScanMessageRole role;
  final String text;
  final Uint8List? imageBytes;
  bool isLoading;
  String? attachmentSummary;

  bool get isUser => role == _ScanMessageRole.user;
}

class _ScanSession {
  _ScanSession({required this.id, required this.startedAt});

  final String id;
  final DateTime startedAt;
  final List<_ScanMessage> messages = [];
  DateTime? closedAt;
  bool hadCall = false;

  bool get isClosed => closedAt != null;

  String get context {
    final lines = <String>[];
    for (final message in messages) {
      if (message.imageBytes != null) {
        final summary = message.attachmentSummary;
        lines.add(
          summary == null || summary.isEmpty
              ? 'Student uploaded a photo.'
              : 'Student uploaded a photo. Image summary: $summary',
        );
      } else if (message.text.trim().isNotEmpty) {
        lines.add(
          '${message.isUser ? 'Student' : 'Marie'}: ${message.text.trim()}',
        );
      }
    }
    final value = lines.join('\n');
    return value.length <= 6000 ? value : value.substring(value.length - 6000);
  }

  List<Map<String, String>> get conversation {
    final turns = <Map<String, String>>[];
    for (final message in messages) {
      final content = message.imageBytes != null
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
    _pipeline = _pipeline.then((_) => _processImage(session, message));
  }

  Future<void> _processImage(_ScanSession session, _ScanMessage message) async {
    try {
      final result = await _scanService.scan(
        imageBytes: message.imageBytes!,
        conversationContext: session.context,
      );
      final reply = result.reply.isNotEmpty
          ? result.reply
          : (result.ocrText.isNotEmpty
                ? result.ocrText
                : "Couldn't read anything useful from that photo.");
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
    } catch (_) {
      message.isLoading = false;
      _appendMessage(
        session,
        _ScanMessage(
          id: const Uuid().v4(),
          role: _ScanMessageRole.assistant,
          text: "Couldn't reach the AI tutor. Check your connection.",
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
      _appendMessage(
        session,
        _ScanMessage(
          id: const Uuid().v4(),
          role: _ScanMessageRole.assistant,
          text: reply.isEmpty ? "I couldn't form an answer just now." : reply,
        ),
      );
    } catch (_) {
      _appendMessage(
        session,
        _ScanMessage(
          id: const Uuid().v4(),
          role: _ScanMessageRole.assistant,
          text: "Couldn't reach the AI tutor. Check your connection.",
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
    final choice = await showPSActionSheet<int>(
      context,
      title: 'Scan sessions',
      actions: [
        for (var i = 0; i < _sessions.length; i++)
          (
            label:
                'Session ${i + 1}${_sessions[i].isClosed ? ' · Closed' : ''}',
            value: i,
            destructive: false,
          ),
        (label: 'New session', value: -1, destructive: false),
      ],
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
    _storage.saveSession(
      Session(
        id: session.id,
        startedAt: session.startedAt.toIso8601String(),
        endedAt: session.closedAt!.toIso8601String(),
        summary: session.hadCall
            ? 'Vision Scan session with voice call'
            : 'Vision Scan session',
        topic: 'Vision Scan',
        stage: 'vision_scan',
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = _activeSession;
    final canCompose = session == null || !session.isClosed;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Scan', style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          _ScanHeaderButton(
            icon: CupertinoIcons.clock,
            label: 'Scan sessions',
            onPressed: _showSessionPicker,
          ),
          InlineCallActions(controller: _call),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SessionToolbar(
              session: session,
              sessionNumber: session == null
                  ? null
                  : _sessions.indexOf(session) + 1,
              onSelect: _showSessionPicker,
              onClose: canCompose ? _closeActiveSession : null,
              onNew: _startNewSession,
            ),
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

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.session,
    required this.sessionNumber,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
  });

  final _ScanSession? session;
  final int? sessionNumber;
  final VoidCallback onSelect;
  final VoidCallback? onClose;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final label = session == null
        ? 'New scan session'
        : 'Session $sessionNumber${session!.isClosed ? ' · Closed' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect,
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Text(
                      label,
                      style: DesignTokens.body(
                        13,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                    const SizedBox(width: 4),
                    const Icon(CupertinoIcons.chevron_down, size: 14),
                  ],
                ),
              ),
            ),
          ),
          if (onClose != null)
            _QuietButton(label: 'Close session', onPressed: onClose!),
          if (session?.isClosed == true)
            _QuietButton(label: 'New session', onPressed: onNew),
        ],
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

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});

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
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                label,
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
