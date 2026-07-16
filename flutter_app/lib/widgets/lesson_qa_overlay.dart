import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../providers/database_provider.dart';
import '../services/lesson_speech_service.dart';
import 'adaptive/adaptive.dart';

/// Bottom-sheet voice Q&A used by every lab: mic → STT → LessonAgentService → TTS reply.
/// Uses the app-wide `LessonSpeechService.shared` instance so narration and Q&A share one
/// audio-session owner.
class LessonQAOverlay extends ConsumerStatefulWidget {
  const LessonQAOverlay({
    super.key,
    required this.lessonContext,
    this.sttLocale = 'en-US',
  });

  final String lessonContext;
  final String sttLocale;

  @override
  ConsumerState<LessonQAOverlay> createState() => _LessonQAOverlayState();

  /// Shows this overlay as an adaptive bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String lessonContext,
    String sttLocale = 'en-US',
  }) async {
    await showPSModalSheet<void>(
      context,
      isScrollControlled: true,
      builder: (_) =>
          LessonQAOverlay(lessonContext: lessonContext, sttLocale: sttLocale),
    );
  }
}

class _LessonQAOverlayState extends ConsumerState<LessonQAOverlay> {
  final LessonSpeechService _speech = LessonSpeechService.shared;

  String _partialTranscript = '';
  String? _answer;
  String? _errorText;
  bool _isListening = false;
  bool _isThinking = false;
  final List<({String role, String text})> _history = [];

  @override
  void dispose() {
    _speech.stopListening();
    super.dispose();
  }

  void _close() {
    _speech.stopListening();
    Navigator.of(context).pop();
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _speech.stopListening();
      setState(() => _isListening = false);
      return;
    }
    await _speech.stop(); // don't listen while narration is speaking
    setState(() {
      _errorText = null;
      _isListening = true;
    });
    await _speech.startListening(
      locale: widget.sttLocale,
      onPartial: (text) {
        if (mounted) setState(() => _partialTranscript = text);
      },
      onFinal: (finalText) {
        if (!mounted) return;
        setState(() => _isListening = false);
        if (finalText.trim().isEmpty) {
          setState(() => _partialTranscript = '');
          return;
        }
        _ask(finalText);
      },
    );
  }

  Future<void> _ask(String question) async {
    setState(() {
      _isThinking = true;
      _answer = null;
      _errorText = null;
    });
    try {
      final reply = await ref
          .read(lessonAgentServiceProvider)
          .askQuestion(
            lessonContext: widget.lessonContext,
            question: question,
            history: List.of(_history),
          );
      if (!mounted) return;
      setState(() {
        _history.add((role: 'user', text: question));
        _history.add((role: 'assistant', text: reply));
        _answer = reply;
        _partialTranscript = '';
        _isThinking = false;
      });
      _speech.speak(
        items: [SpeechItem(text: reply, language: 'en-US')],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString();
        _isThinking = false;
      });
    }
  }

  void _replay() {
    final answer = _answer;
    if (answer == null) return;
    _speech.speak(
      items: [SpeechItem(text: answer, language: 'en-US')],
    );
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
                          : 'Ask with microphone',
                      child: IconButton(
                        onPressed: _isThinking ? null : _toggleMic,
                        style: IconButton.styleFrom(
                          backgroundColor: _isThinking
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
                    if (_isThinking) ...[
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
