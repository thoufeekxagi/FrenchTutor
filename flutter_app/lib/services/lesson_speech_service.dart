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
import 'ai_cost_tracker.dart';
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
  void Function(String transcript, List<int> pcmBytes)? _onListenFinalWithAudio;

  List<SpeechItem> _ttsQueue = [];
  int _ttsIndex = 0;
  // Lines that failed during an explicit playback run. They are reported to
  // the UI and can be retried by an explicit tap; they are never regenerated
  // in a hidden background task.
  final List<SpeechItem> _skippedItems = [];
  void Function(int)? _onItemStart;
  void Function()? _onFinished;
  void Function()? _onPlaybackReady;
  void Function(Object error)? _onError;
  double? _rateOverride;
  double? _playbackSpeedOverride;

  /// Fires with (item index, word index within that item's text) as playback
  /// reaches each word — for word-by-word highlighting during story
  /// narration. Gemini Live returns a raw PCM buffer, not a platform voice
  /// with native word-boundary events, so timing is estimated: each word's
  /// slice of the item's known total playback duration is proportional to
  /// its character length. Approximate, not exact — good enough to track
  /// roughly where the voice is without needing per-phoneme timing data.
  void Function(int itemIndex, int wordIndex)? _onWordBoundary;
  final List<Timer> _wordTimers = [];
  final List<double> _wordOffsetsMs = [];
  double _activePlaybackSpeed = 1.0;
  double _activePlaybackConsumedMs = 0;
  int _activePlaybackDurationMs = 0;
  int _activePlaybackItemIndex = -1;
  int _activePlaybackGeneration = 0;
  DateTime? _activePlaybackStartedAt;
  bool _speakStarting = false;

  bool isSpeaking = false;
  bool isPaused = false;
  bool isListening = false;

  /// Legacy Gemini voice-style rate used by callers that do not provide a
  /// local playback speed. Reading passes [playbackSpeed] instead, so its
  /// speed never changes the generated clip.
  Future<double> get rate async {
    if (_rateOverride != null) return _rateOverride!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble('lesson_narration_rate') ?? 0;
    return stored > 0 ? stored : 0.42;
  }

  /// Speaks a sequence of (text, language) items in order. `onItemStart` fires with the
  /// index of each item as it begins (for UI highlight/scroll); `onFinished` fires once the
  /// whole queue completes (not called if `stop()` is invoked). `rate` retains the legacy
  /// Gemini voice-style override. [playbackSpeed] is a local native-player rate and does not
  /// affect synthesis or the audio cache.
  Future<void> speak({
    required List<SpeechItem> items,
    double? rate,
    double? playbackSpeed,
    void Function(int)? onItemStart,
    void Function()? onFinished,
    void Function(int itemIndex, int wordIndex)? onWordBoundary,
    void Function()? onPlaybackReady,
    void Function(Object error)? onError,
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
      _skippedItems.clear();
      _rateOverride = rate;
      _playbackSpeedOverride = playbackSpeed == null
          ? null
          : _normalizePlaybackSpeed(playbackSpeed);
      _onItemStart = onItemStart;
      _onFinished = onFinished;
      _onWordBoundary = onWordBoundary;
      _onPlaybackReady = onPlaybackReady;
      _onError = onError;
      isPaused = false;
      // Never synthesize the rest of a lesson in the background. A new Live
      // request is allowed only when the learner explicitly starts playback
      // for that item; cached clips remain instant.
      await _speakCurrent(generation);
    } finally {
      _speakStarting = false;
    }
  }

  Future<void> pause() async {
    if (!isSpeaking || isPaused) return;
    _accountPlaybackProgress();
    isPaused = true;
    // Gemini playback is a fire-and-forget PCM buffer, not a resumable
    // stream — stop cleanly now; resume() replays this item from the top.
    _completionTimer?.cancel();
    for (final t in _wordTimers) {
      t.cancel();
    }
    _wordTimers.clear();
    _activePlaybackStartedAt = null;
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
    _onError = null;
    _playbackSpeedOverride = null;
    _resetPlaybackTiming();
  }

  /// Changes playback speed for the current cached/generated clip. This only
  /// updates the native player; it never changes the Gemini prompt, cache key,
  /// or stored PCM bytes.
  Future<void> setPlaybackSpeed(double speed) async {
    final normalized = _normalizePlaybackSpeed(speed);
    if (_playbackSpeedOverride != null) {
      _playbackSpeedOverride = normalized;
    }
    if (isSpeaking && !isPaused && _activePlaybackStartedAt != null) {
      _accountPlaybackProgress();
      _activePlaybackSpeed = normalized;
      _scheduleCompletionTimer();
      _scheduleWordTimers(skipConsumed: true);
    }
    await _geminiAudioLazy?.setPlaybackSpeed(normalized);
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
    final usesLocalPlaybackSpeed = _playbackSpeedOverride != null;
    // Reading passes playbackSpeed, so its speed control always reuses the
    // normal cached clip and never asks Gemini for a slow/fast re-render.
    final isSlow = !usesLocalPlaybackSpeed && speakingRate <= 0.36;
    final playbackSpeed = _playbackSpeedOverride ?? 1.0;
    final persona = ActiveTutor.current;

    final played = await _speakWithGemini(
      item.text,
      voiceName: persona.voiceName,
      slow: isSlow,
      playbackSpeed: playbackSpeed,
      contentItemId: item.contentItemId,
      generation: generation,
    );
    if (!played) {
      // Skip only this line so an explicit playback run can continue. A
      // failed line is retried only when the learner explicitly taps it
      // again; there is no hidden retry after the lesson finishes.
      debugPrint(
        'LessonSpeechService: skipping unplayable line at index $_ttsIndex after retries',
      );
      _skippedItems.add(item);
      // Still surfaces to the caller (a single-item speak, e.g. a vocab
      // word's speaker tap, has nothing to skip to and would otherwise
      // fail with no feedback at all) but never stops the rest of a
      // multi-line story from continuing.
      _onError?.call(StateError('Gemini Live returned no playable audio.'));
      _ttsIndex += 1;
      await _speakCurrent(generation);
    }
  }

  Future<bool> _speakWithGemini(
    String text, {
    required String voiceName,
    required bool slow,
    required double playbackSpeed,
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
      // Narration is a one-shot PCM buffer, not a live conversation chunk.
      // Wait until the serialized native feed has accepted it before clearing
      // the loading state or starting the playback timer. Without this, a
      // first-use player race could report “ready” while the buffer was still
      // queued (or had already been dropped), producing silent narration.
      await _geminiAudio.playAudioChunk(bytes, waitForFeed: true);
      final activePlaybackSpeed = _playbackSpeedOverride == null
          ? playbackSpeed
          : _normalizePlaybackSpeed(_playbackSpeedOverride!);
      await _geminiAudio.setPlaybackSpeed(activePlaybackSpeed);
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
    final activePlaybackSpeed = _playbackSpeedOverride == null
        ? playbackSpeed
        : _normalizePlaybackSpeed(_playbackSpeedOverride!);
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 200;
    _activePlaybackSpeed = activePlaybackSpeed;
    _activePlaybackConsumedMs = 0;
    _activePlaybackDurationMs = playbackMs;
    _activePlaybackItemIndex = myIndex;
    _activePlaybackGeneration = generation;
    _activePlaybackStartedAt = DateTime.now();
    _scheduleCompletionTimer();
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
    // Store timings in source-audio milliseconds. The native player can then
    // reschedule them immediately if the learner changes speed mid-sentence.
    _wordOffsetsMs.clear();
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
      _wordOffsetsMs.add(elapsedMs);
      elapsedMs += (words[i].length + 1) * msPerUnit;
    }
    _scheduleWordTimers();
  }

  void _scheduleWordTimers({bool skipConsumed = false}) {
    for (final timer in _wordTimers) {
      timer.cancel();
    }
    _wordTimers.clear();
    final onWordBoundary = _onWordBoundary;
    if (onWordBoundary == null || _wordOffsetsMs.isEmpty) return;
    final itemIndex = _activePlaybackItemIndex;
    final generation = _activePlaybackGeneration;
    final consumedMs = skipConsumed ? _activePlaybackConsumedMs : 0.0;
    for (var i = 0; i < _wordOffsetsMs.length; i++) {
      final offsetMs = _wordOffsetsMs[i];
      if (skipConsumed && offsetMs <= consumedMs) continue;
      final delayMs = skipConsumed
          ? ((offsetMs - consumedMs) / _activePlaybackSpeed).round()
          : (offsetMs / _activePlaybackSpeed).round();
      _wordTimers.add(
        Timer(Duration(milliseconds: delayMs.clamp(0, 2147483647)), () {
          if (_ttsIndex != itemIndex ||
              isPaused ||
              generation != _queueGeneration) {
            return;
          }
          onWordBoundary(itemIndex, i);
        }),
      );
    }
  }

  void _accountPlaybackProgress() {
    final startedAt = _activePlaybackStartedAt;
    if (startedAt == null) return;
    final elapsedMs =
        DateTime.now().difference(startedAt).inMicroseconds / 1000;
    _activePlaybackConsumedMs += elapsedMs * _activePlaybackSpeed;
    if (_activePlaybackConsumedMs > _activePlaybackDurationMs) {
      _activePlaybackConsumedMs = _activePlaybackDurationMs.toDouble();
    }
    _activePlaybackStartedAt = DateTime.now();
  }

  void _scheduleCompletionTimer() {
    _completionTimer?.cancel();
    if (_activePlaybackDurationMs <= 0 || _activePlaybackStartedAt == null) {
      return;
    }
    final remainingMs = (_activePlaybackDurationMs - _activePlaybackConsumedMs)
        .clamp(0.0, double.infinity)
        .toDouble();
    final delayMs = (remainingMs / _activePlaybackSpeed).round().clamp(
      1,
      2147483647,
    );
    final itemIndex = _activePlaybackItemIndex;
    final generation = _activePlaybackGeneration;
    _completionTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_ttsIndex != itemIndex ||
          isPaused ||
          generation != _queueGeneration) {
        return;
      }
      _activePlaybackStartedAt = null;
      _onUtteranceComplete(generation);
    });
  }

  void _resetPlaybackTiming() {
    _activePlaybackStartedAt = null;
    _activePlaybackConsumedMs = 0;
    _activePlaybackDurationMs = 0;
    _activePlaybackItemIndex = -1;
    _activePlaybackGeneration = 0;
    _wordOffsetsMs.clear();
  }

  /// Resolves one explicit playback request. The normal path is cache-only;
  /// when a reader was opened before its background deck finished, make at
  /// most two bounded generation attempts for that one requested clip. The
  /// audio service deduplicates an already-running deck request, so this does
  /// not create a second billable call for the same sentence.
  Future<List<int>?> synthesizeWithRetry(
    String text, {
    required String voiceName,
    required bool slow,
    String? contentItemId,
  }) async {
    final itemId = contentItemId?.trim();
    if (itemId == null || itemId.isEmpty) return null;
    // generateAndCache performs one cache resolution (local, then Supabase,
    // then Gemini). Do not call loadCachedAudio first: on a true miss that
    // used to perform the same remote lookup twice and made the first line
    // appear to buffer for up to two timeout windows. The deck owns the one
    // delayed retry; an explicit playback tap makes one request only so it
    // cannot create a third hidden provider attempt after the deck failed.
    for (var attempt = 1; attempt <= 1; attempt++) {
      try {
        final generated = await GeminiLiveAudioService.shared.generateAndCache(
          text: text,
          contentItemId: itemId,
          voiceName: voiceName,
          slow: slow,
        );
        if (generated != null && generated.isNotEmpty) return generated;
      } catch (error) {
        debugPrint('LessonSpeechService: TTS attempt $attempt failed: $error');
      }
    }
    debugPrint('LessonSpeechService: TTS request exhausted one attempt');
    return null;
  }

  /// Legacy compatibility hook. Audio is generated by the owning lesson
  /// creation transaction (`LessonAudioDeckService.prepare`), never by a
  /// background prewarm task. Existing callers intentionally become no-ops.
  Future<void> prewarmNarration(List<SpeechItem> items) async {
    return;
  }

  /// Compatibility hook for older callers that used to request a background
  /// batch. It is intentionally a no-op: generated lesson audio is owned by
  /// the explicit lesson/audio-deck transaction, never by a warmup batch.
  Future<void> prewarmNarrationBounded(
    List<SpeechItem> items, {
    int concurrency = 4,
  }) async {
    return;
  }

  /// Copies pre-generated PCM assets into the same persistent cache used by
  /// ordinary Gemini Live narration. This seeds every requested voice variant while
  /// keeping the runtime playback path identical and making the local SQLite
  /// cache index authoritative after the first preload.
  Future<int> prewarmBundled(
    List<SpeechItem> items, {
    int concurrency = 4,
    String? cacheNamespace,
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
          cacheNamespace: cacheNamespace,
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

  double _normalizePlaybackSpeed(double value) {
    if ((value - 0.5).abs() < 0.001) return 0.5;
    if ((value - 0.75).abs() < 0.001) return 0.75;
    if ((value - 1.5).abs() < 0.001) return 1.5;
    return 1.0;
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
    String? cacheNamespace,
  }) async {
    final cacheKey = _diskCacheKey(
      voiceName,
      slow,
      text,
      namespace: cacheNamespace,
    );
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
    String? cacheNamespace,
  }) async {
    final cacheKey = _diskCacheKey(
      voiceName,
      slow,
      text,
      namespace: cacheNamespace,
    );
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

    // Pronunciation clips are independent one-shot buffers. Hard-reset the
    // shared player before feeding the selected clip so a live-call timeline
    // or queued tail can never make a tap appear to do nothing.
    await _geminiAudio.stopPlayback(hardStop: true);
    await _geminiAudio.playAudioChunk(bytes, waitForFeed: true);
  }

  /// Returns only an already-generated PCM16 clip. Playback is read-only:
  /// a cache miss is an error, never an implicit Gemini generation request.
  Future<List<int>> synthesize(
    String text, {
    required String voiceName,
    bool slow = false,
    String? contentItemId,
  }) async {
    final bytes = await loadCachedAudio(text, voiceName: voiceName, slow: slow);
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
  // Persistent cache — generated clips live in the app's support directory and
  // are indexed locally, so replays never make a provider request. A missing
  // clip is surfaced to the caller; it is never silently regenerated.
  // ---------------------------------------------------------------------------

  Directory? _cacheDirLazy;

  Future<Directory> get _cacheDir async {
    if (_cacheDirLazy != null) return _cacheDirLazy!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/gemini_tts_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDirLazy = dir;
  }

  String _diskCacheKey(
    String voiceName,
    bool slow,
    String text, {
    String? namespace,
  }) => sha256
      .convert(utf8.encode('${namespace ?? 'default'}|$voiceName|$slow|$text'))
      .toString();

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
    void Function(String transcript, List<int> pcmBytes)? onFinalWithAudio,
  }) async {
    if (isSpeaking) {
      onFinal('');
      onFinalWithAudio?.call('', const []);
      return;
    }
    await stopListening();

    final granted = await _captureAudio.requestPermission();
    if (!granted) {
      onFinal('');
      onFinalWithAudio?.call('', const []);
      return;
    }

    isListening = true;
    unawaited(
      AiCostTracker.event(
        feature: 'speech_capture',
        event: 'speech_capture_started',
        extra: {'locale': locale, 'auto_stop_seconds': 6},
      ),
    );
    _captureBuffer.clear();
    _onListenFinal = onFinal;
    _onListenFinalWithAudio = onFinalWithAudio;
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
    final audioCallback = _onListenFinalWithAudio;
    _onListenFinal = null;
    _onListenFinalWithAudio = null;
    if (bytes.isEmpty) {
      unawaited(
        AiCostTracker.event(
          feature: 'speech_capture',
          event: 'speech_capture_empty',
        ),
      );
      callback?.call('');
      audioCallback?.call('', const []);
      return;
    }
    try {
      unawaited(
        AiCostTracker.event(
          feature: 'speech_capture',
          event: 'speech_transcription_requested',
          extra: {'pcm_bytes': bytes.length},
        ),
      );
      final text = await LessonAgentService.shared.transcribeSpeech(bytes);
      unawaited(
        AiCostTracker.event(
          feature: 'speech_capture',
          event: 'speech_transcription_finished',
          extra: {'pcm_bytes': bytes.length, 'transcript_length': text.length},
        ),
      );
      callback?.call(text);
      audioCallback?.call(text, bytes);
    } catch (_) {
      unawaited(
        AiCostTracker.event(
          feature: 'speech_capture',
          event: 'speech_transcription_failed',
          extra: {'pcm_bytes': bytes.length},
        ),
      );
      callback?.call('');
      audioCallback?.call('', bytes);
    }
  }

  /// MUST be called before starting a live Marie call (Phase 5) and in dispose of any lesson
  /// screen that used this service, so the audio session can be claimed cleanly elsewhere.
  Future<void> deactivate() async {
    await stop();
    await stopListening();
  }
}
