import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/common.dart';

import '../data/database/tts_audio_cache_store.dart';
import '../models/tutor_persona.dart';
import 'audio_streaming_service.dart';
import 'lesson_agent_service.dart';

class SpeechItem {
  SpeechItem({required this.text, required this.language, this.contentItemId});
  final String text;
  final String language; // "fr-FR" or "en-US"

  /// Optional vocab/grammar/listening/writing item this line belongs to —
  /// purely metadata for the cache index, never required for a cache hit.
  final String? contentItemId;
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

  /// Called once at app startup (see `main.dart`, alongside `ContentService.shared.preload()`)
  /// so this singleton can index cached audio in the app database. Safe to leave
  /// unconfigured (e.g. in tests) — the service just falls back to synthesizing every time.
  static TtsAudioCacheStore? _cacheStore;
  static void configure(CommonDatabase db) {
    _cacheStore = TtsAudioCacheStore(db);
  }

  AudioStreamingService? _geminiAudioLazy;
  AudioStreamingService get _geminiAudio =>
      _geminiAudioLazy ??= AudioStreamingService();
  final Map<String, List<int>> _synthCache = {};
  // Guards concurrent synthesize() calls for the same cache key from racing
  // each other's disk-cache write — without this, two overlapping calls
  // (e.g. auto-narration racing a manual replay tap) both miss the cache,
  // both call Gemini, and both write the same file path at once, which can
  // interleave into a corrupted/misaligned PCM buffer that then plays back
  // as garbled noise FOREVER since the corrupt file is what gets replayed
  // from the persisted disk cache from then on.
  final Map<String, Future<List<int>>> _synthInFlight = {};
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
      contentItemId: item.contentItemId,
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
    String? contentItemId,
  }) async {
    final bytes = await synthesizeWithRetry(
      text,
      voiceName: voiceName,
      slow: slow,
      contentItemId: contentItemId,
    );
    if (bytes == null) return false;
    final myIndex = _ttsIndex;
    await _geminiAudio.playAudioChunk(bytes);
    // PCM16 mono at 24kHz — mark this item done once it has actually sounded.
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 200;
    _completionTimer = Timer(Duration(milliseconds: playbackMs), () {
      if (_ttsIndex != myIndex || isPaused) return;
      _onUtteranceComplete();
    });
    return true;
  }

  /// Reading a whole story fires one fresh synthesis call per sentence in
  /// quick succession (nothing's cached yet on a first read) — enough to hit
  /// the TTS endpoint's per-minute rate limit partway through, which used to
  /// fail every remaining sentence instantly with no audio and no retry (the
  /// highlight still advanced from `_onItemStart`, so it looked like playback
  /// was working while actually going silent). Retries a few times with
  /// backoff before finally giving up on a line — longer backoff
  /// specifically for a 429, since a fixed short delay won't have cleared by
  /// the time it retries. Shared by live playback and [prewarmNarration].
  Future<List<int>?> synthesizeWithRetry(
    String text, {
    required String voiceName,
    required bool slow,
    String? contentItemId,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await synthesize(
          text,
          voiceName: voiceName,
          slow: slow,
          contentItemId: contentItemId,
        );
      } catch (e) {
        debugPrint(
          'LessonSpeechService: TTS synth failed (attempt $attempt/$maxAttempts): $e',
        );
        if (attempt == maxAttempts) return null;
        // NOTE: deliberately no `isPaused` check here — this method is
        // shared by the narration queue, on-demand speaker taps, and
        // background prewarming, and `isPaused` is queue-only state. It has
        // no meaning for the other two callers and was silently cutting
        // their retries short after just one attempt whenever the queue
        // happened to be paused for an unrelated reason.
        final isRateLimited = e is GeminiHttpError && e.isRateLimited;
        await Future.delayed(
          Duration(milliseconds: isRateLimited ? 2500 * attempt : 400 * attempt),
        );
      }
    }
    return null;
  }

  /// Synthesizes and caches every line of a freshly generated story right
  /// after it's written, one at a time (never in parallel — a burst of
  /// simultaneous calls is exactly what trips the rate limit in the first
  /// place), so opening it to read hits the persisted `tts_audio_cache`
  /// (same on-device database the story itself is saved in) instead of
  /// calling the TTS endpoint live for every sentence. Best-effort and
  /// meant to be fired in the background right after generation — any line
  /// that doesn't warm here just falls back to live synthesis (with the
  /// same retry) the first time it's actually played, exactly like before
  /// this existed, so a partial or total failure here is never fatal.
  Future<void> prewarmNarration(List<SpeechItem> items) async {
    final voiceName = ActiveTutor.current.voiceName;
    for (final item in items) {
      await synthesizeWithRetry(
        item.text,
        voiceName: voiceName,
        slow: false,
        contentItemId: item.contentItemId,
      );
    }
  }

  void _onUtteranceComplete() {
    _ttsIndex += 1;
    _speakCurrent();
  }

  /// True if [text] in [voiceName]/[slow] is already synthesized and sitting in
  /// cache (memory or the persisted disk+DB index) — a single cheap, synchronous
  /// SQLite lookup, no disk or network I/O. Lets a play button decide instantly,
  /// before the user even taps, whether it can show a plain "ready to play"
  /// state or needs to show a generating indicator once tapped.
  bool isCached(String text, {required String voiceName, bool slow = false}) {
    final cacheKey = _diskCacheKey(voiceName, slow, text);
    if (_synthCache.containsKey(cacheKey)) return true;
    return _cacheStore?.fileName(cacheKey) != null;
  }

  /// Plays already-resolved PCM16 bytes through this service's own audio
  /// session — for callers that want to play a single clip on demand (a
  /// speaker button) without going through the queued narration path above.
  Future<void> playBytes(List<int> bytes) async {
    // Cuts whatever this shared player is already sounding — without this,
    // two on-demand taps (e.g. two different TtsPlayButton widgets on the
    // same screen) queue back-to-back instead of the newer tap replacing
    // the older one.
    await _geminiAudio.stopPlayback();
    await _geminiAudio.playAudioChunk(bytes);
  }

  /// Returns the PCM16 bytes for [text] in [voiceName], from cache when possible.
  /// Used both by the queued narration path above and directly by callers that just want
  /// one clip played on demand (vocab/grammar/listening speaker buttons, roleplay lines) —
  /// every caller shares the same in-memory + persisted-disk + DB-indexed cache, so a given
  /// line is ever synthesized once, never once per screen.
  Future<List<int>> synthesize(
    String text, {
    required String voiceName,
    bool slow = false,
    String? contentItemId,
  }) async {
    final cacheKey = _diskCacheKey(voiceName, slow, text);
    final cached = _synthCache[cacheKey] ?? await _readDiskCache(cacheKey);
    if (cached != null) {
      _synthCache[cacheKey] = cached;
      return cached;
    }

    // A second caller for the same line while the first is still in flight
    // (auto-narration racing a manual replay, two screens sharing a cached
    // sentence) awaits the SAME synthesis/write instead of kicking off its
    // own — otherwise both would write the same disk-cache file path at
    // once and could interleave into a corrupted buffer.
    final inFlight = _synthInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _synthesizeAndCache(
      cacheKey,
      text,
      voiceName: voiceName,
      slow: slow,
      contentItemId: contentItemId,
    );
    _synthInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _synthInFlight.remove(cacheKey);
    }
  }

  Future<List<int>> _synthesizeAndCache(
    String cacheKey,
    String text, {
    required String voiceName,
    required bool slow,
    String? contentItemId,
  }) async {
    final bytes = await LessonAgentService.shared.synthesizeSpeech(
      text,
      slow: slow,
      voiceName: voiceName,
    );
    _synthCache[cacheKey] = bytes;
    unawaited(
      _writeDiskCache(
        cacheKey,
        bytes,
        voiceName: voiceName,
        slow: slow,
        text: text,
        contentItemId: contentItemId,
      ),
    );
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Persistent cache — the same sentence in the same voice is spoken constantly
  // (flashcards, replays, repeated lesson visits, roleplay lines heard again in a
  // later session); persisting synthesized audio in the app's own support directory
  // (NOT the OS-evictable temp dir) and indexing it in `tts_audio_cache` means most
  // narration is instant instead of a fresh Gemini round-trip, and survives both app
  // relaunches and the OS's temp-storage cleanup sweeps. Self-healing: a cache miss
  // (missing row, or a row whose file somehow vanished) just re-synthesizes.
  // ---------------------------------------------------------------------------

  Directory? _cacheDirLazy;

  Future<Directory> get _cacheDir async {
    if (_cacheDirLazy != null) return _cacheDirLazy!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/gemini_tts_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDirLazy = dir;
  }

  String _diskCacheKey(String voiceName, bool slow, String text) =>
      sha256.convert(utf8.encode('$voiceName|$slow|$text')).toString();

  Future<List<int>?> _readDiskCache(String key) async {
    try {
      final fileName = _cacheStore?.fileName(key) ?? '$key.pcm';
      final file = File('${(await _cacheDir).path}/$fileName');
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {
      // A cache read failure just falls through to fresh synthesis.
    }
    return null;
  }

  Future<void> _writeDiskCache(
    String key,
    List<int> bytes, {
    required String voiceName,
    required bool slow,
    required String text,
    String? contentItemId,
  }) async {
    try {
      final fileName = '$key.pcm';
      final file = File('${(await _cacheDir).path}/$fileName');
      await file.writeAsBytes(bytes, flush: false);
      _cacheStore?.record(
        cacheKey: key,
        voiceName: voiceName,
        slow: slow,
        text: text,
        fileName: fileName,
        contentItemId: contentItemId,
      );
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
