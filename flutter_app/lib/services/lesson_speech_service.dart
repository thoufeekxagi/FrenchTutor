import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechItem {
  SpeechItem({required this.text, required this.language});
  final String text;
  final String language; // "fr-FR" or "en-US"
}

/// TTS + STT for in-lesson narration and voice Q&A. Fully on-device (flutter_tts +
/// speech_to_text) so lessons work at $0 without OpenRouter/Gemini for the voice layer.
///
/// Single-owner rule: this service and the future AudioStreamingService (Marie call) must
/// never both hold the mic/audio session. Callers MUST call `deactivate()` before starting
/// a live call, and this service deactivates itself when idle.
class LessonSpeechService {
  LessonSpeechService._() {
    _tts.setCompletionHandler(_onUtteranceComplete);
    _tts.setCancelHandler(() => isSpeaking = false);
    _tts.setStartHandler(() => isSpeaking = true);
  }

  static final LessonSpeechService shared = LessonSpeechService._();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<SpeechItem> _ttsQueue = [];
  int _ttsIndex = 0;
  void Function(int)? _onItemStart;
  void Function()? _onFinished;
  double? _rateOverride;

  bool isSpeaking = false;
  bool isPaused = false;
  bool isListening = false;

  /// Narration rate: 0.3 (slow) – 0.55 (normal-fast). Persisted via Settings, unless a
  /// one-off override was passed to `speak(items:rate:)`.
  Future<double> get rate async {
    if (_rateOverride != null) return _rateOverride!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble('lesson_narration_rate') ?? 0;
    return stored > 0 ? stored : 0.42;
  }

  /// Speaks a sequence of (text, language) items in order. `onItemStart` fires with the
  /// index of each item as it begins (for UI highlight/scroll); `onFinished` fires once the
  /// whole queue completes (not called if `stop()` is invoked). `rate` overrides the Settings
  /// rate for this utterance only.
  Future<void> speak({
    required List<SpeechItem> items,
    double? rate,
    void Function(int)? onItemStart,
    void Function()? onFinished,
  }) async {
    await stop();
    if (items.isEmpty) {
      onFinished?.call();
      return;
    }
    _ttsQueue = items;
    _ttsIndex = 0;
    _rateOverride = rate;
    _onItemStart = onItemStart;
    _onFinished = onFinished;
    isPaused = false;
    await _speakCurrent();
  }

  Future<void> pause() async {
    if (!isSpeaking || isPaused) return;
    await _tts.pause();
    isPaused = true;
  }

  Future<void> resume() async {
    if (!isPaused) return;
    isPaused = false;
    await _speakCurrent();
  }

  Future<void> stop() async {
    await _tts.stop();
    _ttsQueue = [];
    _ttsIndex = 0;
    isSpeaking = false;
    isPaused = false;
    _onFinished = null;
    _onItemStart = null;
  }

  Future<void> _speakCurrent() async {
    if (_ttsIndex >= _ttsQueue.length) {
      isSpeaking = false;
      final finished = _onFinished;
      _onFinished = null;
      finished?.call();
      return;
    }
    isSpeaking = true;
    final item = _ttsQueue[_ttsIndex];
    _onItemStart?.call(_ttsIndex);

    await _tts.setLanguage(item.language);
    await _tts.setSpeechRate(await rate);
    await _tts.setPitch(1.0);
    await _tts.speak(item.text);
  }

  void _onUtteranceComplete() {
    _ttsIndex += 1;
    _speakCurrent();
  }

  // --- Narration text helpers ---

  static List<SpeechItem> speechItemsFromText(String narration) {
    return _splitSentences(
      narration,
    ).map((s) => SpeechItem(text: s, language: _detectLanguage(s))).toList();
  }

  static List<SpeechItem> speechItemsFromLines(List<String> narrationLines) {
    return narrationLines.expand(speechItemsFromText).toList();
  }

  static List<String> _splitSentences(String text) {
    final raw = text.replaceAll('...', '…').replaceAll('..', '.');
    final pattern = RegExp(r'[.!?…]+');
    final sentences = <String>[];
    var lastEnd = 0;
    for (final match in pattern.allMatches(raw)) {
      final sentence = raw.substring(lastEnd, match.end).trim();
      if (sentence.isNotEmpty) sentences.add(sentence);
      lastEnd = match.end;
    }
    final remaining = raw.substring(lastEnd).trim();
    if (remaining.isNotEmpty) sentences.add(remaining);
    if (sentences.isEmpty) {
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) sentences.add(trimmed);
    }
    return sentences;
  }

  static const _frenchChars = 'éèêëàâçîïôûùœæÉÈÊËÀÂÇÎÏÔÛÙŒ';
  static const _frenchWords = {
    'bonjour',
    'merci',
    'oui',
    'non',
    'je',
    'vous',
    'le',
    'la',
    'les',
    'comment',
    'avec',
    'pour',
    'suis',
    'il',
    'elle',
    'nous',
    'ils',
    'elles',
    'un',
    'une',
    'bien',
    'mal',
    'aussi',
    'mais',
    'et',
    'ou',
    'ne',
    'pas',
    'ai',
    'as',
    'a',
    'avons',
    'avez',
    'ont',
    'sont',
    'être',
    'avoir',
    'aller',
    'faire',
    'dire',
    'voir',
    'savoir',
    'pouvoir',
    'vouloir',
    'devoir',
    'venir',
    'prendre',
    'donner',
    'parler',
    'travaille',
  };

  static String _detectLanguage(String text) {
    final lower = text.toLowerCase();
    if (lower.runes.any((r) => _frenchChars.contains(String.fromCharCode(r)))) {
      return 'fr-FR';
    }
    final words = lower.split(' ').toSet();
    if (words.intersection(_frenchWords).length >= 2) return 'fr-FR';
    return 'en-US';
  }

  // --- STT ---

  /// Starts listening; calls `onPartial` as transcription updates and `onFinal` once with the
  /// final transcript after ~1.5s of silence or when `stopListening()` is called.
  Future<void> startListening({
    String locale = 'en-US',
    required void Function(String) onPartial,
    required void Function(String) onFinal,
  }) async {
    if (isSpeaking) {
      onFinal('');
      return;
    }
    await stopListening();

    final available = await _speech.initialize();
    if (!available) {
      onFinal('');
      return;
    }

    isListening = true;
    var lastTranscript = '';
    await _speech.listen(
      onResult: (result) {
        lastTranscript = result.recognizedWords;
        onPartial(lastTranscript);
        if (result.finalResult) {
          isListening = false;
          onFinal(lastTranscript);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        pauseFor: const Duration(milliseconds: 1500),
        listenFor: const Duration(seconds: 30),
        localeId: locale,
      ),
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    isListening = false;
  }

  /// MUST be called before starting a live Marie call (Phase 5) and in dispose of any lesson
  /// screen that used this service, so the audio session can be claimed cleanly elsewhere.
  Future<void> deactivate() async {
    await stop();
    await stopListening();
  }
}
