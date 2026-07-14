import '../../widgets/adaptive/adaptive.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/chat_message.dart';
import '../../flow/stage_outcome.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/floating_notetaker.dart';

enum CallStatus { connecting, listening, tutorSpeaking, muted, ended }

/// Free-form (or context-seeded) live voice call with Marie. Ported from SessionView.swift.
/// `stage` is null for the unstructured "Just talk to Marie" call, or e.g. "speaking" for the
/// Daily Pathway's closing roleplay stage — it only affects how the saved session is tagged.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.apiKey, this.lessonContext, this.stage, this.dailySessionId});

  final String apiKey;
  final String? lessonContext;
  final String? stage;

  /// Set when this call is the Daily Pathway's speaking stage — links the
  /// ai_sessions record to today's pathway row.
  final String? dailySessionId;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  final List<ChatMessage> _messages = [];
  CallStatus _callStatus = CallStatus.connecting;
  String _errorMessage = '';
  bool _sessionSaved = false;
  int _callDuration = 0;
  bool _isSpeakerOn = true;

  // Real evidence for the coordinator's completion threshold (P0.3) and for
  // honest history (the old code saved startedAt == endedAt == save time).
  DateTime? _connectedAt;
  int _userUtteranceCount = 0;
  String _endedReason = 'cancelled';
  String? _aiSessionRecordId;

  Timer? _timer;
  final ScrollController _scrollController = ScrollController();

  late final GeminiLiveService _gemini;
  late final AudioStreamingService _audio;
  final String _sessionId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    LessonSpeechService.shared.deactivate();
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Speaking';
    });
    _audio = AudioStreamingService();
    _gemini = GeminiLiveService(
      apiKey: widget.apiKey,
      lessonContext: widget.lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
    );
    _setupCallbacks();
    _startCall();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _endCall();
    _scrollController.dispose();
    super.dispose();
  }

  void _startCall() {
    _gemini.connect();
  }

  void _endCall() {
    if (_sessionSaved) return;
    _sessionSaved = true;

    _timer?.cancel();
    _audio.stopStreaming();
    _audio.dispose();
    _gemini.disconnect();
    if (mounted) setState(() => _callStatus = CallStatus.ended);

    final recordId = _aiSessionRecordId;
    if (recordId != null) {
      ref.read(learningStoreProvider).endAiSession(
            recordId,
            endedReason: _endedReason,
            learnerUtteranceCount: _userUtteranceCount,
          );
    }
    _saveSessionLocally();
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _audio.setSpeakerEnabled(_isSpeakerOn);
  }

  Future<void> _toggleMute() async {
    if (_callStatus == CallStatus.muted) {
      try {
        await _audio.startStreaming(onChunk: _gemini.sendAudioChunk);
        setState(() => _callStatus = CallStatus.listening);
      } catch (e) {
        setState(() => _errorMessage = 'Failed to unmute: $e');
      }
    } else {
      await _audio.stopStreaming();
      setState(() => _callStatus = CallStatus.muted);
    }
  }

  void _setupCallbacks() {
    _gemini.onConnected = () async {
      if (!mounted) return;
      _connectedAt = DateTime.now();
      _aiSessionRecordId = ref.read(learningStoreProvider).startAiSession(
            dailySessionId: widget.dailySessionId,
            stage: widget.stage,
            topic: widget.lessonContext != null ? 'lesson' : 'free_talk',
          );
      setState(() => _callStatus = CallStatus.listening);
      _startTimer();

      final granted = await _audio.requestPermission();
      if (!mounted) return;
      if (granted) {
        try {
          await _audio.startStreaming(onChunk: _gemini.sendAudioChunk);
          _gemini.sendText(
            "(Le student vient de rejoindre l'appel. Salue-le chaleureusement en français et demande ce qu'il veut pratiquer aujourd'hui.)",
          );
        } catch (e) {
          setState(() => _errorMessage = 'Mic error: $e');
        }
      } else {
        setState(() => _errorMessage = 'Microphone permission denied');
      }
    };

    _gemini.onDisconnected = () {
      if (!mounted || _sessionSaved) return;
      _endedReason = 'disconnected';
      setState(() {
        _errorMessage = 'Connection lost';
        _callStatus = CallStatus.ended;
      });
    };

    _gemini.onError = (msg) {
      if (!mounted) return;
      setState(() => _errorMessage = msg);
    };

    _gemini.onUserTranscript = (text) {
      _userUtteranceCount += 1;
      if (!mounted) return;
      _appendMessage(ChatMessage(role: 'user', content: text));
    };

    _gemini.onTutorTranscript = (text) {
      if (!mounted) return;
      _appendMessage(ChatMessage(role: 'tutor', content: text));
    };

    _gemini.onAudioChunk = (audioData) {
      _audio.isOutputActive = true;
      _audio.playAudioChunk(audioData);
      if (mounted && _callStatus != CallStatus.tutorSpeaking) {
        setState(() => _callStatus = CallStatus.tutorSpeaking);
      }
    };

    _gemini.onTurnComplete = () {
      _audio.isOutputActive = false;
      if (mounted) setState(() => _callStatus = CallStatus.listening);
    };

    _gemini.onInterrupted = () {
      _audio.isOutputActive = false;
      _audio.stopPlayback();
      if (mounted) setState(() => _callStatus = CallStatus.listening);
    };
  }

  void _appendMessage(ChatMessage message) {
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callDuration += 1);
    });
  }

  void _saveSessionLocally() {
    final now = DateTime.now();
    final summary = _generateLocalSummary();

    final session = Session(
      id: _sessionId,
      startedAt: (_connectedAt ?? now.subtract(Duration(seconds: _callDuration))).toIso8601String(),
      endedAt: now.toIso8601String(),
      summary: summary,
      stage: widget.stage,
    );
    final storage = ref.read(storageServiceProvider);
    storage.saveSession(session);
    for (final msg in _messages) {
      storage.saveMessage(sessionId: _sessionId, role: msg.isUser ? 'user' : 'assistant', content: msg.content);
    }

    if (_callDuration >= 45) {
      ref.read(learningStoreProvider).markHabit('speaking', minutes: (_callDuration / 60).clamp(1, 999).round());
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop(SpeakingResult(
          connected: _connectedAt != null,
          durationSeconds: _callDuration,
          learnerUtteranceCount: _userUtteranceCount,
          endedReason: _endedReason,
        ));
      }
    });
  }

  String _generateLocalSummary() {
    if (_messages.isEmpty) return 'No conversation recorded.';

    final userMessages = _messages.where((m) => m.isUser).length;
    final tutorMessages = _messages.where((m) => !m.isUser).length;
    final duration = _formatDuration(_callDuration);

    var summary = 'Session lasted $duration. ';
    summary += '$userMessages exchanges from you, $tutorMessages responses from tutor. ';

    final allText = _messages.map((m) => m.content).join(' ').toLowerCase();
    const frenchKeywords = {
      'bonjour', 'merci', 'oui', 'non', 'je', 'vous', 'le', 'la', 'les', 'comment', 'avec', 'pour',
      'suis', 'appelle', 'salut', 'ça', 'va', 'très', 'bien', 'mal', 'aussi', 'mais', 'et', 'ou',
      'ne', 'pas', 'ai', 'as', 'a', 'avons', 'avez', 'ont', 'sont', 'être', 'avoir', 'aller',
      'faire', 'dire', 'voir', 'savoir', 'pouvoir', 'vouloir', 'devoir', 'falloir', 'venir',
      'prendre', 'donner', 'parler', 'écouter', 'regarder', 'aimer', 'manger', 'boire', 'acheter',
      'vendre', 'habiter', 'travailler', 'étudier', 'apprendre', 'comprendre', 'répéter',
      'corriger', 'expliquer', 'traduire',
    };
    final words = allText.split(' ').toSet();
    final frenchUsed = words.intersection(frenchKeywords).toList()..sort();
    if (frenchUsed.isNotEmpty) {
      summary += 'French words used: ${frenchUsed.take(10).join(', ')}. ';
    }

    summary += userMessages > 3 ? 'Good practice session — keep going!' : 'Try speaking more next time for better practice.';
    return summary;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Color get _statusColor {
    switch (_callStatus) {
      case CallStatus.connecting:
        return const Color(0xFFF29A19);
      case CallStatus.listening:
        return const Color(0xFF33C759);
      case CallStatus.tutorSpeaking:
        return Passeport.brass;
      case CallStatus.muted:
        return Passeport.slate;
      case CallStatus.ended:
        return Passeport.slate.withValues(alpha: 0.5);
    }
  }

  String get _statusText {
    switch (_callStatus) {
      case CallStatus.connecting:
        return 'Connecting…';
      case CallStatus.listening:
        return 'Listening — speak in French';
      case CallStatus.tutorSpeaking:
        return 'Marie is speaking…';
      case CallStatus.muted:
        return 'Microphone muted';
      case CallStatus.ended:
        return 'Call ended';
    }
  }

  Future<void> _confirmEnd() async {
    final shouldEnd = await showPSConfirmDialog(
      context,
      title: 'End Call?',
      message: "Your session transcript and summary will be saved.",
      confirmLabel: 'End Call',
      destructive: true,
    );
    if (shouldEnd) {
      _endedReason = 'completed';
      _endCall();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notetaker = ref.watch(notetakerStateProvider);
    // Matches iOS's fullScreenCover, which has no swipe-to-dismiss gesture at all — without
    // this, Flutter's iOS edge-swipe-back gesture (still active even on a fullscreenDialog
    // MaterialPageRoute) can silently end the call, bypassing the "End Call?" confirmation
    // entirely. canPop stays false permanently: the confirmation dialog's own Navigator.pop()
    // call bypasses canPop since it's a direct pop, not a system-initiated one, so confirming
    // still works normally.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
      backgroundColor: Passeport.parchmentDim,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _callHeader(),
                Expanded(child: _transcriptView()),
                if (_errorMessage.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    color: Passeport.maroon.withValues(alpha: 0.1),
                    child: Text(
                      _errorMessage,
                      style: Passeport.mono(12).copyWith(color: Passeport.maroon),
                    ),
                  ),
                _callControls(),
              ],
            ),
            FloatingNotetakerOverlay(state: notetaker),
          ],
        ),
      ),
      ),
    );
  }

  Widget _callHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: _confirmEnd,
                child: const Icon(Icons.close, size: 20, color: Passeport.ink),
              ),
              const Spacer(),
              Text(
                _formatDuration(_callDuration),
                style: Passeport.mono(15, weight: FontWeight.w500).copyWith(color: Passeport.slateDim),
              ),
              const Spacer(),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Column(
            children: [
              Text('French Tutor', style: Passeport.display(20, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_statusText, style: Passeport.body(13).copyWith(color: Passeport.slateDim)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _transcriptView() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_in_talk, size: 48, color: Passeport.slate.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              _callStatus == CallStatus.connecting ? 'Connecting to your tutor...' : 'Start speaking to begin',
              style: Passeport.body(14).copyWith(color: Passeport.slateDim),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _MessageBubble(message: _messages[index]),
      ),
    );
  }

  Widget _callControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            icon: _callStatus == CallStatus.muted ? Icons.mic_off : Icons.mic,
            label: _callStatus == CallStatus.muted ? 'Muted' : 'Mic On',
            color: _callStatus == CallStatus.muted ? Passeport.slate : Passeport.brass,
            onTap: (_callStatus == CallStatus.connecting || _callStatus == CallStatus.ended) ? null : _toggleMute,
          ),
          _controlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
            label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
            color: _isSpeakerOn ? Passeport.brass : Passeport.slate,
            onTap: (_callStatus == CallStatus.connecting || _callStatus == CallStatus.ended) ? null : _toggleSpeaker,
          ),
          _controlButton(
            icon: Icons.call_end,
            label: 'End Call',
            color: Passeport.maroon,
            onTap: _confirmEnd,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) _avatar(false),
        if (!isUser) const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? Passeport.maroon : Passeport.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              message.content,
              style: Passeport.body(13.5).copyWith(color: isUser ? Colors.white : Passeport.text),
            ),
          ),
        ),
        if (isUser) const SizedBox(width: 8),
        if (isUser) _avatar(true),
      ],
    );
  }

  Widget _avatar(bool isUser) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: (isUser ? Passeport.maroon : Passeport.brass).withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isUser ? Icons.person : Icons.school,
        size: 14,
        color: isUser ? Passeport.maroon : Passeport.brass,
      ),
    );
  }
}
