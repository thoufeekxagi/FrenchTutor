import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tutor_persona.dart';
import 'audio_streaming_service.dart';
import 'lesson_agent_service.dart';

class SpeechItem {
  SpeechItem({required this.text, required this.language});
  final String text;
  final String language; // "fr-FR" or "en-US"
}

/// TTS + STT for in-lesson narration and voice Q&A — Gemini only, by design.
///
/// Narration is synthesized by Gemini TTS in the learner's chosen tutor
/// persona voice ([ActiveTutor.current]), and speech capture is transcribed
/// by Gemini too. There is deliberately NO on-device speech engine anywhere
/// in this service — no flutter_tts, no speech_to_text — a practice session
/// must sound and listen like the tutor the learner picked, never a generic
/// device voice/recognizer. If a Gemini call fails, the affected line is
/// skipped rather than silently substituted with a device voice.
///
/// Single-owner rule: this service and the future AudioStreamingService (Marie call) must
/// never both hold the mic/audio session. Callers MUST call `deactivate()` before starting
/// a live call, and this service deactivates itself when idle.
class LessonSpeechService {
  LessonSpeechService._();

  static final LessonSpeechService shared = LessonSpeechService._();

  AudioStreamingService? _geminiAudioLazy;
  AudioStreamingService get _geminiAudio =>
      _geminiAudioLazy ??= AudioStreamingService();
  final Map<String, List<int>> _synthCache = {};
  Timer? _completionTimer;

  AudioStreamingService? _captureAudioLazy;
  AudioStreamingService get _captureAudio =>
      _captureAudioLazy ??= AudioStreamingService();
  final List<int> _captureBuffer = [];
  Timer? _captureAutoStopTimer;
  void Function(String)? _onListenFinal;

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
    isPaused = true;
    // Gemini playback is a fire-and-forget PCM buffer, not a resumable
    // stream — stop cleanly now; resume() replays this item from the top.
    _completionTimer?.cancel();
    await _geminiAudioLazy?.stopPlayback();
  }

  Future<void> resume() async {
    if (!isPaused) return;
    isPaused = false;
    await _speakCurrent();
  }

  Future<void> stop() async {
    _completionTimer?.cancel();
    _completionTimer = null;
    await _geminiAudioLazy?.stopPlayback();
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

    final speakingRate = await rate;
    final isSlow = speakingRate <= 0.36;
    final persona = ActiveTutor.current;

    final played = await _speakWithGemini(
      item.text,
      voiceName: persona.voiceName,
      slow: isSlow,
    );
    if (!played) {
      // Gemini is the only voice engine here — no on-device fallback. Skip
      // this line rather than substitute a device voice, or hang forever.
      _onUtteranceComplete();
    }
  }

  Future<bool> _speakWithGemini(
    String text, {
    required String voiceName,
    required bool slow,
  }) async {
    try {
      final cacheKey = _diskCacheKey(voiceName, slow, text);
      var bytes = _synthCache[cacheKey];
      bytes ??= await _readDiskCache(cacheKey);
      if (bytes == null) {
        bytes = await LessonAgentService.shared.synthesizeSpeech(
          text,
          slow: slow,
          voiceName: voiceName,
        );
        unawaited(_writeDiskCache(cacheKey, bytes));
      }
      _synthCache[cacheKey] = bytes;
      final myIndex = _ttsIndex;
      await _geminiAudio.playAudioChunk(bytes);
      // PCM16 mono at 24kHz — mark this item done once it has actually sounded.
      final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 200;
      _completionTimer = Timer(Duration(milliseconds: playbackMs), () {
        if (_ttsIndex != myIndex || isPaused) return;
        _onUtteranceComplete();
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onUtteranceComplete() {
    _ttsIndex += 1;
    _speakCurrent();
  }

  // ---------------------------------------------------------------------------
  // Disk cache — the same sentence in the same voice is spoken constantly
  // (flashcards, replays, repeated lesson visits); persisting synthesized
  // audio across app launches means most narration is instant instead of a
  // fresh Gemini round-trip every time. Self-healing: a cache miss just
  // re-synthesizes, so it's safe for the OS to clear this directory.
  // ---------------------------------------------------------------------------

  Directory? _cacheDirLazy;

  Future<Directory> get _cacheDir async {
    if (_cacheDirLazy != null) return _cacheDirLazy!;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/gemini_tts_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDirLazy = dir;
  }

  String _diskCacheKey(String voiceName, bool slow, String text) =>
      sha256.convert(utf8.encode('$voiceName|$slow|$text')).toString();

  Future<List<int>?> _readDiskCache(String key) async {
    try {
      final file = File('${(await _cacheDir).path}/$key.pcm');
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {
      // A cache read failure just falls through to fresh synthesis.
    }
    return null;
  }

  Future<void> _writeDiskCache(String key, List<int> bytes) async {
    try {
      final file = File('${(await _cacheDir).path}/$key.pcm');
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // Best-effort — narration already played from the in-memory bytes.
    }
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

  // --- STT (Gemini only — see class doc) ---

  /// Starts capturing the mic; `onPartial` is never called (Gemini transcribes
  /// once, on `stopListening()`, not incrementally) but is kept in the
  /// signature so existing callers don't need to change. `onFinal` fires with
  /// the transcript once capture stops, or `''` if nothing usable was heard.
  /// Auto-stops after 6s so a forgotten mic can't run forever.
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

    final granted = await _captureAudio.requestPermission();
    if (!granted) {
      onFinal('');
      return;
    }

    isListening = true;
    _captureBuffer.clear();
    _onListenFinal = onFinal;
    await _captureAudio.startStreaming(onChunk: _captureBuffer.addAll);
    _captureAutoStopTimer?.cancel();
    _captureAutoStopTimer = Timer(const Duration(seconds: 6), stopListening);
  }

  Future<void> stopListening() async {
    if (!isListening) return;
    _captureAutoStopTimer?.cancel();
    isListening = false;
    await _captureAudio.stopStreaming();
    final bytes = List<int>.of(_captureBuffer);
    _captureBuffer.clear();
    final callback = _onListenFinal;
    _onListenFinal = null;
    if (bytes.isEmpty) {
      callback?.call('');
      return;
    }
    try {
      final text = await LessonAgentService.shared.transcribeSpeech(bytes);
      callback?.call(text);
    } catch (_) {
      callback?.call('');
    }
  }

  /// MUST be called before starting a live Marie call (Phase 5) and in dispose of any lesson
  /// screen that used this service, so the audio session can be claimed cleanly elsewhere.
  Future<void> deactivate() async {
    await stop();
    await stopListening();
  }
}
