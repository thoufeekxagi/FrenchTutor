import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../providers.dart';
import '../services/audio_service.dart';
import '../services/websocket_service.dart';

class SessionScreen extends StatefulWidget {
  final String serverUrl;

  const SessionScreen({super.key, required this.serverUrl});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final WebSocketService _ws;
  late final AudioService _audio;
  late final String _sessionId;

  final List<ChatMessage> _messages = [];
  SessionStatus _status = SessionStatus.idle;
  bool _isRecording = false;
  bool _sessionActive = false;
  String _errorMessage = '';
  StreamSubscription? _statusSub;
  StreamSubscription? _transcriptSub;
  StreamSubscription? _audioSub;
  StreamSubscription? _summarySub;
  StreamSubscription? _errorSub;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4();
    _ws = WebSocketService(serverUrl: widget.serverUrl);
    _audio = AudioService();
    _setupListeners();
    _connectAndStart();
  }

  void _setupListeners() {
    _statusSub = _ws.status.listen((status) {
      setState(() => _status = status);
    });

    _transcriptSub = _ws.transcript.listen((data) {
      final parts = data.split('|');
      if (parts.length >= 2) {
        final role = parts[0];
        final text = parts.sublist(1).join('|');
        setState(() {
          _messages.add(ChatMessage(role: role, content: text));
        });
        _scrollToBottom();
      }
    });

    _audioSub = _ws.audio.listen((bytes) async {
      await _audio.playAudioBytes(bytes);
    });

    _summarySub = _ws.summary.listen((summary) async {
      await _saveSession(summary);
    });

    _errorSub = _ws.errors.listen((error) {
      setState(() => _errorMessage = error);
    });
  }

  Future<void> _connectAndStart() async {
    _ws.connect(_sessionId);
    await Future.delayed(const Duration(milliseconds: 500));
    _ws.sendStart();
    setState(() => _sessionActive = true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleRecording() async {
    if (_status == SessionStatus.thinking || _status == SessionStatus.speaking) {
      return;
    }

    if (_isRecording) {
      final bytes = await _audio.stopRecording();
      setState(() => _isRecording = false);
      _ws.sendAudio(bytes);
    } else {
      try {
        await _audio.startRecording();
        setState(() {
          _isRecording = true;
          _errorMessage = '';
        });
      } catch (e) {
        setState(() => _errorMessage = 'Mic error: $e');
      }
    }
  }

  Future<void> _endSession() async {
    _ws.sendEnd();
  }

  Future<void> _saveSession(String summary) async {
    final storage = AppProviders.storageOf(context);
    final session = Session(
      id: _sessionId,
      startedAt: DateTime.now().toIso8601String(),
      endedAt: DateTime.now().toIso8601String(),
      summary: summary,
    );
    await storage.saveSession(session);

    for (final msg in _messages) {
      await storage.saveMessage(_sessionId, msg.role, msg.content);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _transcriptSub?.cancel();
    _audioSub?.cancel();
    _summarySub?.cancel();
    _errorSub?.cancel();
    _ws.dispose();
    _audio.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white70),
          onPressed: () => _confirmEnd(),
        ),
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _statusText,
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _endSession,
            child: Text(
              'End',
              style: GoogleFonts.poppins(
                color: const Color(0xFFFF6B6B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildTranscript()),
          if (_errorMessage.isNotEmpty) _buildErrorBar(),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildTranscript() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.messageCircle, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'Start speaking to begin your lesson',
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessage(_messages[index]),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(false),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF6C5CE7).withValues(alpha: 0.15)
                    : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
              ),
              child: Text(
                msg.content,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: isUser ? Colors.white : Colors.white70,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _buildAvatar(true),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0xFF6C5CE7).withValues(alpha: 0.2)
            : const Color(0xFF8B7CF6).withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isUser ? LucideIcons.user : LucideIcons.graduationCap,
        size: 14,
        color: isUser ? const Color(0xFF6C5CE7) : const Color(0xFF8B7CF6),
      ),
    );
  }

  Widget _buildErrorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
      child: Text(
        _errorMessage,
        style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFFF6B6B)),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: GestureDetector(
        onTap: _toggleRecording,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: _isRecording
                ? const Color(0xFFFF6B6B).withValues(alpha: 0.15)
                : const Color(0xFF6C5CE7).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isRecording
                  ? const Color(0xFFFF6B6B)
                  : const Color(0xFF6C5CE7),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _isRecording ? LucideIcons.square : LucideIcons.mic,
                size: 32,
                color: _isRecording
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF6C5CE7),
              ),
              const SizedBox(height: 6),
              Text(
                _isRecording ? 'Tap to send' : _statusLabel,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (_status) {
      case SessionStatus.listening:
        return const Color(0xFF4ADE80);
      case SessionStatus.thinking:
        return const Color(0xFFFBBF24);
      case SessionStatus.speaking:
        return const Color(0xFF6C5CE7);
      default:
        return Colors.white24;
    }
  }

  String get _statusText {
    switch (_status) {
      case SessionStatus.listening:
        return 'Listening';
      case SessionStatus.thinking:
        return 'Thinking...';
      case SessionStatus.speaking:
        return 'Speaking...';
      case SessionStatus.ended:
        return 'Session Ended';
      default:
        return 'Connecting...';
    }
  }

  String get _statusLabel {
    switch (_status) {
      case SessionStatus.thinking:
        return 'Processing...';
      case SessionStatus.speaking:
        return 'Tutor is speaking';
      default:
        return 'Tap to speak';
    }
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          'End Session?',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        content: Text(
          'Your session summary will be saved.',
          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _endSession();
            },
            child: Text(
              'End',
              style: GoogleFonts.poppins(color: const Color(0xFFFF6B6B)),
            ),
          ),
        ],
      ),
    );
  }
}
