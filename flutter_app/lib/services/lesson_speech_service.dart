import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/common.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database/tts_audio_cache_store.dart';
import '../models/tutor_persona.dart';
import 'audio_streaming_service.dart';
import 'gemini_live_audio_service.dart';
import 'lesson_agent_service.dart';

class SpeechItem {
  SpeechItem({
    required this.text,
    required this.language,
    this.contentItemId,
    this.voiceName,
    this.assetPath,
  });
  final String text;
  final String language; // "fr-FR" or "en-US"

  /// Optional vocab/grammar/listening/writing item this line belongs to —
  /// purely metadata for the cache index, never required for a cache hit.
  final String? contentItemId;

  /// Optional voice override used by offline pre-generated catalogs.
  final String? voiceName;

  /// Optional bundled PCM asset used by offline pre-generated catalogs.
  final String? assetPath;
}

/// Gemini Live audio + STT for in-lesson narration and voice Q&A.
///
/// Narration is synthesized by Gemini Live in the learner's chosen tutor
/// persona voice ([ActiveTutor.current]), and speech capture is transcribed
/// by Gemini too. There is deliberately no TTS endpoint or on-device speech engine anywhere
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
  final Map<String, Future<List<int>?>> _bundledInFlight = {};
  // Guards concurrent synthesize() calls for the same cache key from racing
  // each other's disk-cache write — without this, two overlapping calls
  // (e.g. auto-narration racing a manual replay tap) both miss the cache,
  // both call Gemini, and both write the same file path at once, which can
  // interleave into a corrupted/misaligned PCM buffer that then plays back
  // as garbled noise FOREVER since the corrupt file is what gets replayed
  // from the persisted disk cache from then on.
  Timer? _completionTimer;

  /// Every queued narration request owns a generation. If a learner changes
  /// line or stage while synthesis is still in flight, the old request is
  /// allowed to finish its cache write but is never allowed to play or call
  /// callbacks into the new lesson state.
  int _queueGeneration = 0;

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
  void Function()? _onPlaybackReady;
  double? _rateOverride;

  /// Fires with (item index, word index within that item's text) as playback
  /// reaches each word — for word-by-word highlighting during story
  /// narration. Gemini Live returns a raw PCM buffer, not a platform voice
  /// with native word-boundary events, so timing is estimated: each word's
  /// slice of the item's known total playback duration is proportional to
  /// its character length. Approximate, not exact — good enough to track
  /// roughly where the voice is without needing per-phoneme timing data.
  void Function(int itemIndex, int wordIndex)? _onWordBoundary;
  final List<Timer> _wordTimers = [];
  bool _speakStarting = false;

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
    void Function(int itemIndex, int wordIndex)? onWordBoundary,
    void Function()? onPlaybackReady,
  }) async {
    // A tap should claim the loading slot before the first await. This keeps
    // rapid taps from cancelling the first request and stacking duplicate
    // Gemini/TTS work while the first line is still being prepared. Once the
    // first clip is ready, a new intentional speak request may replace it.
    if (_speakStarting) return;
    _speakStarting = true;
    try {
      await stop();
      if (items.isEmpty) {
        onFinished?.call();
        return;
      }
      final generation = ++_queueGeneration;
      _ttsQueue = items;
      _ttsIndex = 0;
      _rateOverride = rate;
      _onItemStart = onItemStart;
      _onFinished = onFinished;
      _onWordBoundary = onWordBoundary;
      _onPlaybackReady = onPlaybackReady;
      isPaused = false;
      await _speakCurrent(generation);
    } finally {
      _speakStarting = false;
    }
  }

  Future<void> pause() async {
    if (!isSpeaking || isPaused) return;
    isPaused = true;
    // Gemini playback is a fire-and-forget PCM buffer, not a resumable
    // stream — stop cleanly now; resume() replays this item from the top.
    _completionTimer?.cancel();
    for (final t in _wordTimers) {
      t.cancel();
    }
    _wordTimers.clear();
    await _geminiAudioLazy?.stopPlayback();
  }

  Future<void> resume() async {
    if (!isPaused) return;
    isPaused = false;
    await _speakCurrent(_queueGeneration);
  }

  Future<void> stop() async {
    _queueGeneration++;
    _completionTimer?.cancel();
    _completionTimer = null;
    for (final t in _wordTimers) {
      t.cancel();
    }
    _wordTimers.clear();
    await _geminiAudioLazy?.stopPlayback();
    _ttsQueue = [];
    _ttsIndex = 0;
    isSpeaking = false;
    isPaused = false;
    _onFinished = null;
    _onItemStart = null;
    _onWordBoundary = null;
    _onPlaybackReady = null;
  }

  Future<void> _speakCurrent(int generation) async {
    if (generation != _queueGeneration) return;
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
      generation: generation,
    );
    if (!played) {
      // Gemini is the only voice engine here — no on-device fallback. Skip
      // this line rather than substitute a device voice, or hang forever.
      _onUtteranceComplete(generation);
    }
  }

  Future<bool> _speakWithGemini(
    String text, {
    required String voiceName,
    required bool slow,
    String? contentItemId,
    required int generation,
  }) async {
    final bytes = await synthesizeWithRetry(
      text,
      voiceName: voiceName,
      slow: slow,
      contentItemId: contentItemId,
    );
    if (bytes == null) return false;
    if (generation != _queueGeneration) return false;
    final myIndex = _ttsIndex;
    try {
      await _geminiAudio.playAudioChunk(bytes);
    } catch (error, stackTrace) {
      debugPrint(
        'LessonSpeechService: Gemini Live playback failed: $error\n$stackTrace',
      );
      return false;
    }
    if (generation != _queueGeneration) return false;
    // Only remove the loading state after the shared native player has
    // accepted the clip. Previously this callback fired before player
    // startup, so a startup failure looked like a ready-but-silent lesson.
    _onPlaybackReady?.call();
    // PCM16 mono at 24kHz — mark this item done once it has actually sounded.
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 200;
    _completionTimer = Timer(Duration(milliseconds: playbackMs), () {
      if (_ttsIndex != myIndex || isPaused || generation != _queueGeneration) {
        return;
      }
      _onUtteranceComplete(generation);
    });
    _scheduleWordBoundaries(
      text,
      playbackMs: playbackMs,
      itemIndex: myIndex,
      generation: generation,
    );
    return true;
  }

  void _scheduleWordBoundaries(
    String text, {
    required int playbackMs,
    required int itemIndex,
    required int generation,
  }) {
    final onWordBoundary = _onWordBoundary;
    if (onWordBoundary == null) return;
    // Previous item's timers have either already fired or are now no-ops
    // (guarded by the itemIndex check below) — clear the list so it doesn't
    // grow for the whole length of a long story.
    _wordTimers.clear();
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return;
    // +1 per word for the space that follows it (except the last), so the
    // proportion matches roughly how long each word actually takes to say.
    final totalUnits = words.fold<int>(0, (sum, w) => sum + w.length + 1) - 1;
    final msPerUnit = totalUnits > 0 ? playbackMs / totalUnits : 0.0;
    var elapsedMs = 0.0;
    for (var i = 0; i < words.length; i++) {
      final wordIndex = i;
      _wordTimers.add(
        Timer(Duration(milliseconds: elapsedMs.round()), () {
          if (_ttsIndex != itemIndex ||
              isPaused ||
              generation != _queueGeneration) {
            return;
          }
          onWordBoundary(itemIndex, wordIndex);
        }),
      );
      elapsedMs += (words[i].length + 1) * msPerUnit;
    }
  }

  /// Reading a whole story fires one fresh synthesis call per sentence in
  /// quick succession (nothing's cached yet on a first read) — enough to hit
  /// the Live socket quota partway through, which used to
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
          Duration(
            milliseconds: isRateLimited ? 2500 * attempt : 400 * attempt,
          ),
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
  /// opening a Live socket for every sentence. Best-effort and
  /// meant to be fired in the background right after generation — any line
  /// that doesn't warm here just falls back to live synthesis (with the
  /// same retry) the first time it's actually played, exactly like before
  /// this existed, so a partial or total failure here is never fatal.
  Future<void> prewarmNarration(List<SpeechItem> items) async {
    if (items.isEmpty) return;
    final voiceName = ActiveTutor.current.voiceName;
    await GeminiLiveAudioService.shared.resolve(
      text: items.first.text,
      contentItemId: items.first.contentItemId ?? 'narration:0',
      voiceName: voiceName,
    );
    if (items.length > 1) {
      unawaited(
        GeminiLiveAudioService.shared.warmDeck(
          voiceName: voiceName,
          items: [
            for (var index = 1; index < items.length; index++)
              (
                text: items[index].text,
                contentItemId: items[index].contentItemId ?? 'narration:$index',
              ),
          ],
        ),
      );
    }
  }

  /// Same as [prewarmNarration], but runs up to [concurrency] requests at
  /// once instead of one at a time — for a large one-off batch (e.g. every
  /// letter of the alphabet, ~30 short clips) where strictly sequential
  /// synthesis is safe but slow, and the caller needs it to finish faster
  /// without firing all items simultaneously and risking a rate-limit burst.
  /// Each worker still goes through [synthesizeWithRetry], so an individual
  /// clip's failure/backoff behavior is identical to the sequential path.
  Future<void> prewarmNarrationBounded(
    List<SpeechItem> items, {
    int concurrency = 4,
  }) async {
    if (items.isEmpty) return;
    final voiceName = ActiveTutor.current.voiceName;
    await GeminiLiveAudioService.shared.resolve(
      text: items.first.text,
      contentItemId: items.first.contentItemId ?? 'narration:0',
      voiceName: voiceName,
    );
    if (items.length > 1) {
      await GeminiLiveAudioService.shared.warmDeck(
        voiceName: voiceName,
        items: [
          for (var index = 1; index < items.length; index++)
            (
              text: items[index].text,
              contentItemId: items[index].contentItemId ?? 'narration:$index',
            ),
        ],
      );
    }
  }

  /// Copies pre-generated PCM assets into the same persistent cache used by
  /// ordinary Gemini Live narration. This seeds every requested voice variant while
  /// keeping the runtime playback path identical and making the local SQLite
  /// cache index authoritative after the first preload.
  Future<int> prewarmBundled(
    List<SpeechItem> items, {
    int concurrency = 4,
  }) async {
    var next = 0;
    Future<int> worker() async {
      var seeded = 0;
      while (true) {
        if (next >= items.length) return seeded;
        final item = items[next++];
        final assetPath = item.assetPath;
        final voiceName = item.voiceName;
        if (assetPath == null || voiceName == null) continue;
        final bytes = await loadBundledAudio(
          assetPath,
          text: item.text,
          voiceName: voiceName,
          contentItemId: item.contentItemId,
        );
        if (bytes != null) seeded++;
      }
    }

    final seeded = await Future.wait(
      List.generate(concurrency, (_) => worker()),
    );
    var total = 0;
    for (final count in seeded) {
      total += count;
    }
    return total;
  }

  void _onUtteranceComplete(int generation) {
    if (generation != _queueGeneration) return;
    _ttsIndex += 1;
    _speakCurrent(generation);
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

  /// Loads one pre-generated PCM asset, copies it into the persistent cache,
  /// and returns it for immediate playback. A missing asset is a hard miss —
  /// this method never calls Gemini, which keeps the alphabet lesson fully
  /// deterministic and prevents an English pronunciation fallback.
  Future<List<int>?> loadBundledAudio(
    String assetPath, {
    required String text,
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

    final inFlight = _bundledInFlight[cacheKey];
    if (inFlight != null) return inFlight;
    final future = _loadBundledAndCache(
      assetPath,
      cacheKey: cacheKey,
      text: text,
      voiceName: voiceName,
      slow: slow,
      contentItemId: contentItemId,
    );
    _bundledInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _bundledInFlight.remove(cacheKey);
    }
  }

  Future<List<int>?> _loadBundledAndCache(
    String assetPath, {
    required String cacheKey,
    required String text,
    required String voiceName,
    required bool slow,
    String? contentItemId,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes)
          .toList(growable: false);
      if (bytes.isEmpty || bytes.length.isOdd) return null;
      _synthCache[cacheKey] = bytes;
      await _writeDiskCache(
        cacheKey,
        bytes,
        voiceName: voiceName,
        slow: slow,
        text: text,
        contentItemId: contentItemId,
      );
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Loads a public pre-generated alphabet clip from Supabase Storage and
  /// stores it in the same persistent cache as bundled audio. A network or
  /// storage miss returns null so the caller can use its bundled fallback.
  Future<List<int>?> loadRemoteAudio(
    String storagePath, {
    required String text,
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
    try {
      final bytes = await Supabase.instance.client.storage
          .from('alphabet-audio')
          .download(storagePath);
      if (bytes.isEmpty || bytes.length.isOdd) return null;
      final resolved = bytes.toList(growable: false);
      _synthCache[cacheKey] = resolved;
      await _writeDiskCache(
        cacheKey,
        resolved,
        voiceName: voiceName,
        slow: slow,
        text: text,
        contentItemId: contentItemId,
      );
      return resolved;
    } catch (_) {
      return null;
    }
  }

  /// Plays already-resolved PCM16 bytes through this service's own audio
  /// session — for callers that want to play a single clip on demand (a
  /// speaker button) without going through the queued narration path above.
  Future<void> playBytes(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length.isOdd) {
      throw StateError('Invalid PCM16 playback buffer');
    }

    // Pronunciation taps are independent one-shot clips, not a continuation
    // of the live conversation stream. A hard reset removes bytes already
    // accepted by flutter_sound and starts a clean native stream, which avoids
    // the old clip being muted/unmuted over the new one and fixes silent replay
    // after the first pronunciation tap.
    await _geminiAudio.stopPlayback(hardStop: true);
    await _geminiAudio.playAudioChunk(bytes, waitForFeed: true);
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
    final bytes = await GeminiLiveAudioService.shared.resolve(
      text: text,
      contentItemId: contentItemId ?? 'audio:${text.trim()}',
      voiceName: voiceName,
      slow: slow,
    );
    if (bytes == null) throw StateError('Gemini Live returned no audio');
    return bytes;
  }

  /// Reads an existing PCM clip without falling back to live synthesis. This
  /// is for pronunciation buttons that must reuse the audio deck already
  /// prepared for a lesson.
  Future<List<int>?> loadCachedAudio(
    String text, {
    String? voiceName,
    bool slow = false,
  }) async {
    final resolvedVoice = voiceName ?? ActiveTutor.current.voiceName;
    final cacheKey = _diskCacheKey(resolvedVoice, slow, text);
    final lessonCache = _synthCache[cacheKey] ?? await _readDiskCache(cacheKey);
    if (lessonCache != null && lessonCache.isNotEmpty) {
      _synthCache[cacheKey] = lessonCache;
      return lessonCache;
    }

    // The newer Gemini Live cache is keyed separately and may contain the
    // prewarmed PCM even when the legacy lesson cache does not.
    return GeminiLiveAudioService.shared.loadCached(
      text: text,
      voiceName: resolvedVoice,
      slow: slow,
    );
  }

  // ---------------------------------------------------------------------------
  // Persistent cache — the same sentence in the same voice is spoken constantly
  // (flashcards, replays, repeated lesson visits, roleplay lines heard again in a
  // later session); persisting synthesized audio in the app's own support directory
  // (NOT the OS-evictable temp dir) and indexing it in the legacy local cache means most
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
