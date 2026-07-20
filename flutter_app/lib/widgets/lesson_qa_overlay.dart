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

/// Bottom-sheet voice Q&A used by every lab: mic → Gemini Live (in the
/// learner's chosen tutor voice) → spoken reply, one question at a time.
///
/// Gemini only, no on-device speech engine anywhere in this flow. If the
/// live connection can't be established (offline, API error), the mic
/// button surfaces a plain error and the learner can retry — it never
/// silently switches to a device voice/recognizer.
class LessonQAOverlay extends ConsumerStatefulWidget {
  const LessonQAOverlay({super.key, required this.lessonContext});

  final String lessonContext;

  @override
  ConsumerState<LessonQAOverlay> createState() => _LessonQAOverlayState();

  /// Shows this overlay as an adaptive bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String lessonContext,
  }) async {
    await showPSModalSheet<void>(
      context,
      isScrollControlled: true,
      builder: (_) => LessonQAOverlay(lessonContext: lessonContext),
    );
  }
}

class _LessonQAOverlayState extends ConsumerState<LessonQAOverlay> {
  final LessonSpeechService _speech = LessonSpeechService.shared;

  GeminiLiveService? _gemini;
  AudioStreamingService? _audio;

  String _partialTranscript = '';
  String? _answer;
  String? _errorText;
  bool _isListening = false;
  bool _isConnecting = false;
  bool _isThinking = false;
  final List<({String role, String text})> _history = [];

  @override
  void dispose() {
    _speech.stopListening();
    _audio?.stopStreaming();
    _audio?.dispose();
    _gemini?.disconnect();
    super.dispose();
  }

  void _close() {
    _speech.stopListening();
    _audio?.stopStreaming();
    _gemini?.disconnect();
    Navigator.of(context).pop();
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _audio?.stopStreaming();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    setState(() {
      _errorText = null;
      _answer = null;
      _partialTranscript = '';
    });

    if (_gemini == null) {
      final accepted = await AiVoiceDisclosure.ensureAccepted(context);
      if (!mounted) return;
      if (!accepted) return;
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
    }

    final granted = await _audio!.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _errorText = 'Microphone permission denied');
      return;
    }
    setState(() => _isListening = true);
    await _audio!.startStreaming(onChunk: _gemini!.sendAudioChunk);
  }

  /// Opens one Gemini Live connection for this overlay's lifetime — a fresh
  /// question just reuses it, no reconnect logic needed for a single sheet.
  /// Returns whether it actually connected.
  Future<bool> _connectLive() async {
    final completer = Completer<bool>();
    final audio = AudioStreamingService();
    final gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: LiveSessionType.labAssistant,
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
      if (mounted) setState(() => _isThinking = false);
    };
    gemini.onDisconnected = () {
      if (!completer.isCompleted) completer.complete(false);
    };
    gemini.onUserTranscript = (text) {
      if (mounted) setState(() => _partialTranscript = text);
    };
    gemini.onTutorTranscript = (text) {
      if (!mounted) return;
      setState(() {
        _history.add((role: 'user', text: _partialTranscript));
        _history.add((role: 'assistant', text: text));
        _answer = text;
      });
    };
    gemini.onAudioChunk = (bytes) {
      audio.isOutputActive = true;
      audio.playAudioChunk(bytes);
    };
    gemini.onTurnComplete = () {
      audio.isOutputActive = false;
      if (mounted) {
        setState(() {
          _isListening = false;
          _isThinking = false;
        });
      }
      audio.stopStreaming();
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
    } else {
      setState(() => _isThinking = true);
    }
    return connected;
  }

  void _replay() {
    final answer = _answer;
    if (answer == null) return;
    _speech.speak(items: [SpeechItem(text: answer, language: 'en-US')]);
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
                        "Ask Marie's assistant",
                        style: DesignTokens.display(18),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _close,
                      constraints: const BoxConstraints(
                        minWidth: DesignTokens.minTapTarget,
                        minHeight: DesignTokens.minTapTarget,
                      ),
                      icon: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: DesignTokens.slate,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_partialTranscript.isNotEmpty || _isListening)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _partialTranscript.isEmpty
                                  ? 'Listening…'
                                  : _partialTranscript,
                              style: DesignTokens.body(14).copyWith(
                                color: DesignTokens.slateDim,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (_answer != null)
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
                                    _answer!,
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
                    if (_answer != null) ...[
                      IconButton(
                        tooltip: 'Replay answer',
                        onPressed: _replay,
                        icon: const Icon(
                          CupertinoIcons.speaker_2_fill,
                          size: 18,
                          color: DesignTokens.slateDim,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: DesignTokens.parchmentDim,
                          shape: const CircleBorder(),
                          fixedSize: const Size.square(
                            DesignTokens.minTapTarget,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.space4),
                    ],
                    Semantics(
                      button: true,
                      label: _isListening
                          ? 'Stop listening'
                          : _isConnecting
                          ? 'Connecting'
                          : 'Ask with microphone',
                      child: IconButton(
                        onPressed: (_isThinking || _isConnecting)
                            ? null
                            : _toggleMic,
                        style: IconButton.styleFrom(
                          backgroundColor: (_isThinking || _isConnecting)
                              ? DesignTokens.slate
                              : DesignTokens.primary,
                          disabledBackgroundColor: DesignTokens.slate,
                          foregroundColor: DesignTokens.surface,
                          disabledForegroundColor: DesignTokens.surface,
                          fixedSize: const Size.square(64),
                          shape: const CircleBorder(),
                        ),
                        icon: Icon(
                          _isListening
                              ? CupertinoIcons.mic_fill
                              : CupertinoIcons.mic,
                          size: 22,
                        ),
                      ),
                    ),
                    if (_isThinking || _isConnecting) ...[
                      const SizedBox(width: DesignTokens.space4),
                      const SizedBox.square(
                        dimension: DesignTokens.minTapTarget,
                        child: Center(child: PSProgressIndicator()),
                      ),
                    ],
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
