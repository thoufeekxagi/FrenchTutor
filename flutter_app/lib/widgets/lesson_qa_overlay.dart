import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../providers/database_provider.dart';
import '../services/lesson_speech_service.dart';

/// Bottom-sheet voice Q&A used by every lab: mic → STT → LessonAgentService → TTS reply.
/// Uses the app-wide `LessonSpeechService.shared` instance so narration and Q&A share one
/// audio-session owner.
class LessonQAOverlay extends ConsumerStatefulWidget {
  const LessonQAOverlay({super.key, required this.lessonContext, this.sttLocale = 'en-US'});

  final String lessonContext;
  final String sttLocale;

  @override
  ConsumerState<LessonQAOverlay> createState() => _LessonQAOverlayState();

  /// Shows this overlay as a bottom sheet, matching the iOS `.sheet(...).presentationDetents([.medium])`.
  static Future<void> show(
    BuildContext context, {
    required String lessonContext,
    String sttLocale = 'en-US',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LessonQAOverlay(lessonContext: lessonContext, sttLocale: sttLocale),
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
      final reply = await ref.read(lessonAgentServiceProvider).askQuestion(
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
      _speech.speak(items: [SpeechItem(text: reply, language: 'en-US')]);
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
    _speech.speak(items: [SpeechItem(text: answer, language: 'en-US')]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          color: Passeport.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Passeport.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    "Ask Marie's assistant",
                    style: Passeport.display(15, weight: FontWeight.w500),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _close,
                    icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Passeport.slate, size: 20),
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
                            _partialTranscript.isEmpty ? 'Listening…' : _partialTranscript,
                            style: Passeport.body(13.5).copyWith(
                              color: Passeport.slateDim,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      if (_answer != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(CupertinoIcons.sparkles, size: 13, color: Passeport.brass),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_answer!, style: Passeport.body(13.5).copyWith(color: Passeport.text)),
                              ),
                            ],
                          ),
                        ),
                      if (_errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _errorText!,
                            style: Passeport.mono(11).copyWith(color: Passeport.maroon),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_answer != null) ...[
                    IconButton(
                      onPressed: _replay,
                      icon: const Icon(CupertinoIcons.speaker_2_fill, size: 16, color: Passeport.slateDim),
                      style: IconButton.styleFrom(
                        backgroundColor: Passeport.parchmentDim,
                        shape: const CircleBorder(),
                        fixedSize: const Size(44, 44),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  GestureDetector(
                    onTap: _isThinking ? null : _toggleMic,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _isThinking ? Passeport.slate : Passeport.brass,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  if (_isThinking) ...[
                    const SizedBox(width: 16),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Passeport.maroon),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
