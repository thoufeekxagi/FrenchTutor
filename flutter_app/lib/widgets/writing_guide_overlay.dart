import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_keys.dart';
import '../design/tokens.dart';
import '../prompts/live_prompts.dart';
import '../services/audio_streaming_service.dart';
import '../services/gemini_live_service.dart';
import '../services/lesson_speech_service.dart';
import 'adaptive/adaptive.dart';
import 'ai_voice_disclosure.dart';

/// The Writing lab's "call" button, as an inline overlay instead of a route
/// push to a separate live-call screen — the learner never leaves the
/// writing screen. Opens already knowing the task and the learner's current
/// draft (via [lessonContext]), and speaks with the `writingGuide` persona,
/// which is instructed to point at issues rather than state corrections.
class WritingGuideOverlay extends ConsumerStatefulWidget {
  const WritingGuideOverlay({super.key, required this.lessonContext});

  final String lessonContext;

  @override
  ConsumerState<WritingGuideOverlay> createState() =>
      _WritingGuideOverlayState();

  /// Shows this overlay as an adaptive bottom sheet over the current screen.
  static Future<void> show(
    BuildContext context, {
    required String lessonContext,
  }) async {
    await showPSModalSheet<void>(
      context,
      isScrollControlled: true,
      builder: (_) => WritingGuideOverlay(lessonContext: lessonContext),
    );
  }
}

class _WritingGuideOverlayState extends ConsumerState<WritingGuideOverlay> {
  final LessonSpeechService _speech = LessonSpeechService.shared;

  GeminiLiveService? _gemini;
  AudioStreamingService? _audio;

  bool _isConnecting = false;
  bool _isMuted = false;
  bool _tutorSpeaking = false;
  String? _errorText;
  final List<({String role, String text})> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _speech.stopListening();
    _audio?.stopStreaming();
    _audio?.dispose();
    _gemini?.disconnect();
    super.dispose();
  }

  Future<void> _start() async {
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!mounted) return;
    if (!accepted) {
      Navigator.of(context).pop();
      return;
    }
    _speech.deactivate();
    setState(() => _isConnecting = true);
    final connected = await _connectLive();
    if (!mounted) return;
    setState(() => _isConnecting = false);
    if (!connected) {
      setState(
        () => _errorText = "Couldn't connect. Check your connection and try again.",
      );
      return;
    }
    final granted = await _audio!.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _errorText = 'Microphone permission denied');
      return;
    }
    await _audio!.startStreaming(onChunk: _gemini!.sendAudioChunk);
  }

  Future<bool> _connectLive() async {
    final completer = Completer<bool>();
    final audio = AudioStreamingService();
    final gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: LiveSessionType.writingGuide,
      lessonContext: widget.lessonContext,
      autoReconnect: false,
    );
    _audio = audio;
    _gemini = gemini;

    gemini.onConnected = () {
      if (!completer.isCompleted) completer.complete(true);
    };
    gemini.onError = (msg) {
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      if (mounted) setState(() => _errorText = msg);
    };
    gemini.onDisconnected = () {
      if (!completer.isCompleted) completer.complete(false);
    };
    gemini.onUserTranscript = (text) {};
    gemini.onTutorTranscript = (text) {
      if (!mounted) return;
      setState(() => _history.add((role: 'assistant', text: text)));
    };
    gemini.onAudioChunk = (bytes) {
      audio.isOutputActive = true;
      _tutorSpeaking = true;
      audio.playAudioChunk(bytes);
    };
    gemini.onTurnComplete = () {
      audio.isOutputActive = false;
      if (mounted) setState(() => _tutorSpeaking = false);
    };

    gemini.connect();
    final connected = await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );
    if (!connected) {
      gemini.disconnect();
      await audio.dispose();
      _gemini = null;
      _audio = null;
    }
    return connected;
  }

  Future<void> _toggleMute() async {
    if (_audio == null) return;
    if (_isMuted) {
      setState(() => _isMuted = false);
      await _audio!.startStreaming(onChunk: _gemini!.sendAudioChunk);
    } else {
      await _audio!.stopStreaming();
      if (mounted) setState(() => _isMuted = true);
    }
  }

  void _end() {
    _audio?.stopStreaming();
    _gemini?.disconnect();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusCard),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.screenMargin,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: DesignTokens.space2),
                Container(
                  width: 36,
                  height: DesignTokens.space1,
                  decoration: BoxDecoration(
                    color: DesignTokens.hairline,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusPill,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.space3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Writing guide',
                        style: DesignTokens.display(18),
                      ),
                    ),
                    Text(
                      _isConnecting
                          ? 'Connecting…'
                          : _tutorSpeaking
                          ? 'Speaking…'
                          : 'Listening…',
                      style: DesignTokens.mono(
                        10.5,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.space2),
                Text(
                  "She'll point you toward what to fix, not hand you the answer.",
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final turn in _history)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: DesignTokens.space3,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  CupertinoIcons.sparkles,
                                  size: 16,
                                  color: DesignTokens.info,
                                ),
                                const SizedBox(width: DesignTokens.space2),
                                Expanded(
                                  child: Text(
                                    turn.text,
                                    style: DesignTokens.body(
                                      14,
                                    ).copyWith(color: DesignTokens.text),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_errorText != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: DesignTokens.space3,
                            ),
                            child: Text(
                              _errorText!,
                              style: DesignTokens.body(
                                12,
                              ).copyWith(color: DesignTokens.primary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.space4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: _isMuted ? 'Unmute' : 'Mute',
                      onPressed: _isConnecting ? null : _toggleMute,
                      style: IconButton.styleFrom(
                        backgroundColor: DesignTokens.parchmentDim,
                        shape: const CircleBorder(),
                        fixedSize: const Size.square(
                          DesignTokens.minTapTarget,
                        ),
                      ),
                      icon: Icon(
                        _isMuted
                            ? CupertinoIcons.mic_slash_fill
                            : CupertinoIcons.mic_fill,
                        color: DesignTokens.slateDim,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space4),
                    if (_isConnecting)
                      const SizedBox.square(
                        dimension: DesignTokens.minTapTarget,
                        child: Center(child: PSProgressIndicator()),
                      )
                    else
                      IconButton(
                        tooltip: 'End',
                        onPressed: _end,
                        style: IconButton.styleFrom(
                          backgroundColor: DesignTokens.primary,
                          foregroundColor: DesignTokens.surface,
                          fixedSize: const Size.square(64),
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(CupertinoIcons.phone_down_fill, size: 22),
                      ),
                  ],
                ),
                const SizedBox(height: DesignTokens.space3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
