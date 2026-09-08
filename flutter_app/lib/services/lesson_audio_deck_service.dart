import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database/app_migrations.dart';
import '../models/content_models.dart';
import 'gemini_live_audio_service.dart';
import 'ai_cost_tracker.dart';
import '../models/tutor_persona.dart';

/// Prepares the immutable sentence PCM deck shared by Reading, Listening,
/// Course, and Practice.
///
/// GeminiLiveAudioService already owns the durable PCM implementation: it
/// checks the local file, checks the private Supabase object, generates only
/// on a true miss, writes the local file, and mirrors the bytes remotely. This
/// service adds the lesson-level manifest and a single in-flight coordinator
/// so two screens can never render the same sentence twice.
class LessonAudioDeckService {
  LessonAudioDeckService._();

  static final shared = LessonAudioDeckService._();

  final Map<String, Future<bool>> _inFlight = {};

  Future<bool> prepare({
    required GeneratedStory story,
    required CommonDatabase db,
  }) {
    runAppMigrations(db);
    final voiceName = ActiveTutor.current.voiceName;
    final key = '${story.id}|$voiceName';
    final existing = _inFlight[key];
    if (existing != null) {
      unawaited(
        AiCostTracker.event(
          feature: 'lesson_audio_deck',
          event: 'deck_prepare_deduplicated',
          requestId: story.id,
          extra: {
            'lesson_id': story.id,
            'segment_count': story.passage.segments.length,
            'voice': voiceName,
          },
        ),
      );
      return existing;
    }
    unawaited(
      AiCostTracker.event(
        feature: 'lesson_audio_deck',
        event: 'deck_prepare_started',
        requestId: story.id,
        extra: {
          'lesson_id': story.id,
          'segment_count': story.passage.segments.length,
          'voice': voiceName,
        },
      ),
    );
    final operation = usesSharedCourseWav(story)
        ? _prepareSharedCourseWav(story: story, db: db, voiceName: voiceName)
        : _prepareUnshared(story: story, db: db, voiceName: voiceName);
    _inFlight[key] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_inFlight[key], operation)) _inFlight.remove(key);
      }),
    );
    return operation;
  }

  /// The authored Unit 2 listening lesson is one shared WAV. Importing it is
  /// deliberately separate from the personalized sentence path: a cache miss
  /// here is a Storage download plus local slicing, never a Gemini request.
  static bool usesSharedCourseWav(GeneratedStory story) {
    final path = story.audioPath?.trim() ?? '';
    // `pcm-deck-v1:unit-two-listening` was briefly written to cloud rows by
    // the broken client. Treat that legacy marker as the same authored asset
    // so existing installs recover without a regeneration or a migration call.
    return path.startsWith('course-shared/') ||
        (story.id == 'unit-two-listening' &&
            path == 'pcm-deck-v1:unit-two-listening');
  }

  Future<bool> _prepareSharedCourseWav({
    required GeneratedStory story,
    required CommonDatabase db,
    required String voiceName,
  }) async {
    final storedPath = story.audioPath?.trim();
    final path = storedPath?.startsWith('course-shared/') == true
        ? storedPath
        : story.id == 'unit-two-listening'
        ? 'course-shared/unit-two-listening.wav'
        : null;
    if (path == null || path.isEmpty || story.passage.segments.isEmpty) {
      return false;
    }
    try {
      final encoded = await Supabase.instance.client.storage
          .from('listening-audio')
          .download(path)
          .timeout(const Duration(seconds: 12));
      final pcm = extractPcm16Wav(encoded);
      if (pcm == null || pcm.isEmpty) return false;
      final chunks = splitPcmIntoSegments(
        pcm,
        story.passage.segments.map((segment) => segment.fr).toList(),
      );
      if (chunks.length != story.passage.segments.length) return false;
      for (var index = 0; index < chunks.length; index++) {
        final text = story.passage.segments[index].fr.trim();
        final bytes = await GeminiLiveAudioService.shared.cacheLocally(
          text: text,
          bytes: chunks[index],
          contentItemId: story.segmentContentId(index),
          voiceName: voiceName,
        );
        if (bytes == null || bytes.isEmpty || bytes.length.isOdd) {
          return false;
        }
        _upsert(
          db: db,
          story: story,
          index: index,
          text: text,
          voiceName: voiceName,
          cacheKey: GeminiLiveAudioService.cacheKeyFor(
            text: text,
            voiceName: voiceName,
          ),
          status: 'local_ready',
        );
      }
      unawaited(
        AiCostTracker.event(
          feature: 'lesson_audio_deck',
          event: 'shared_course_audio_imported',
          requestId: story.id,
          extra: {
            'lesson_id': story.id,
            'audio_path': path,
            'segment_count': chunks.length,
            'wav_bytes': encoded.length,
            'provider_calls': 0,
          },
        ),
      );
      return true;
    } catch (_) {
      unawaited(
        AiCostTracker.event(
          feature: 'lesson_audio_deck',
          event: 'shared_course_audio_import_failed',
          requestId: story.id,
          extra: {'lesson_id': story.id, 'audio_path': path},
        ),
      );
      return false;
    }
  }

  /// Extracts PCM16 data from a standard RIFF/WAVE file. The shared generator
  /// emits 24 kHz mono PCM16; rejecting other formats prevents invalid audio
  /// from reaching the raw PCM player.
  static Uint8List? extractPcm16Wav(List<int> encoded) {
    final bytes = Uint8List.fromList(encoded);
    if (bytes.length < 12 ||
        _fourCc(bytes, 0) != 'RIFF' ||
        _fourCc(bytes, 8) != 'WAVE') {
      return null;
    }
    final view = ByteData.sublistView(bytes);
    var offset = 12;
    var channels = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;
    int? dataOffset;
    int? dataLength;
    while (offset + 8 <= bytes.length) {
      final id = _fourCc(bytes, offset);
      final chunkLength = view.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (payload > bytes.length) break;
      final end = math.min(bytes.length, payload + chunkLength);
      if (id == 'fmt ' && end - payload >= 16) {
        final format = view.getUint16(payload, Endian.little);
        channels = view.getUint16(payload + 2, Endian.little);
        sampleRate = view.getUint32(payload + 4, Endian.little);
        bitsPerSample = view.getUint16(payload + 14, Endian.little);
        if (format != 1) return null;
      } else if (id == 'data') {
        dataOffset = payload;
        dataLength = end - payload;
        break;
      }
      offset = payload + chunkLength + (chunkLength.isOdd ? 1 : 0);
    }
    if (channels != 1 ||
        sampleRate != GeminiLiveAudioService.outputSampleRateHz ||
        bitsPerSample != 16 ||
        dataOffset == null ||
        dataLength == null ||
        dataLength == 0 ||
        dataLength.isOdd) {
      return null;
    }
    return Uint8List.fromList(
      bytes.sublist(dataOffset, dataOffset + dataLength),
    );
  }

  /// Splits the shared track at silence boundaries. If a renderer changes its
  /// pause profile, weighted sentence boundaries remain a deterministic local
  /// fallback; no transcription or model call is needed.
  static List<Uint8List> splitPcmIntoSegments(
    List<int> pcm,
    List<String> sentenceTexts,
  ) {
    if (sentenceTexts.isEmpty || pcm.isEmpty || pcm.length.isOdd) return [];
    if (sentenceTexts.length == 1) return [Uint8List.fromList(pcm)];
    final sampleCount = pcm.length ~/ 2;
    final view = ByteData.sublistView(Uint8List.fromList(pcm));
    const frameSamples = 240; // 10 ms at 24 kHz
    const silenceThreshold = 700;
    const minimumSilenceFrames = 8;
    final candidates = <int>[];
    var silenceStart = -1;
    var silenceFrames = 0;
    for (
      var frameStart = 0;
      frameStart < sampleCount;
      frameStart += frameSamples
    ) {
      final frameEnd = math.min(sampleCount, frameStart + frameSamples);
      var energy = 0;
      for (var sample = frameStart; sample < frameEnd; sample++) {
        energy += view.getInt16(sample * 2, Endian.little).abs();
      }
      final average = energy ~/ math.max(1, frameEnd - frameStart);
      if (average <= silenceThreshold) {
        silenceStart = silenceStart < 0 ? frameStart : silenceStart;
        silenceFrames++;
      } else if (silenceStart >= 0 && silenceFrames >= minimumSilenceFrames) {
        candidates.add((silenceStart + frameStart) ~/ 2);
        silenceStart = -1;
        silenceFrames = 0;
      } else {
        silenceStart = -1;
        silenceFrames = 0;
      }
    }
    final weights = sentenceTexts
        .map((text) => math.max(1, text.trim().length))
        .toList();
    final totalWeight = weights.fold<int>(0, (sum, value) => sum + value);
    final boundaries = <int>[];
    var prefix = 0;
    for (var index = 0; index < sentenceTexts.length - 1; index++) {
      prefix += weights[index];
      final ideal = (sampleCount * prefix / totalWeight).round();
      final candidate = candidates
          .where(
            (value) =>
                value > sampleCount * 0.03 &&
                value < sampleCount * 0.97 &&
                !boundaries.contains(value),
          )
          .fold<int?>(null, (best, value) {
            if (best == null || (value - ideal).abs() < (best - ideal).abs()) {
              return value;
            }
            return best;
          });
      boundaries.add(candidate ?? ideal);
    }
    boundaries.sort();
    final points = <int>[0, ...boundaries, sampleCount];
    final result = <Uint8List>[];
    for (var index = 0; index < points.length - 1; index++) {
      final start = math.max(0, math.min(sampleCount, points[index]));
      final end = math.max(start + 1, math.min(sampleCount, points[index + 1]));
      result.add(Uint8List.fromList(pcm.sublist(start * 2, end * 2)));
    }
    return result.length == sentenceTexts.length ? result : [];
  }

  static String _fourCc(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));

  bool isPrepared({required GeneratedStory story, required CommonDatabase db}) {
    runAppMigrations(db);
    final voiceName = ActiveTutor.current.voiceName;
    final rows = db.select(
      '''SELECT COUNT(*) AS count FROM lesson_audio_decks
         WHERE lesson_id = ? AND voice_name = ? AND status = 'local_ready' ''',
      [story.id, voiceName],
    );
    final count = (rows.first['count'] as num?)?.toInt() ?? 0;
    return count == story.passage.segments.length && count > 0;
  }

  Future<bool> _prepareUnshared({
    required GeneratedStory story,
    required CommonDatabase db,
    required String voiceName,
  }) async {
    if (story.passage.segments.isEmpty) return false;
    // Two bounded workers keep the deck close to real time without opening a
    // provider-sized burst for every sentence. A failed sentence is retried
    // once in a second wave while the other sentences continue progressing.
    const workerCount = 2;
    var pending = List<int>.generate(story.passage.segments.length, (i) => i);
    var attempt = 1;
    while (pending.isNotEmpty && attempt <= 2) {
      final wave = pending;
      final failed = <int>[];
      var nextIndex = 0;
      Future<void> worker() async {
        while (true) {
          final cursor = nextIndex++;
          if (cursor >= wave.length) return;
          final index = wave[cursor];
          final prepared = await _prepareSegment(
            story: story,
            db: db,
            index: index,
            voiceName: voiceName,
            attempt: attempt,
          );
          if (!prepared) failed.add(index);
        }
      }

      await Future.wait(
        List.generate(math.min(workerCount, wave.length), (_) => worker()),
      );
      pending = failed;
      if (pending.isNotEmpty && attempt == 1) {
        unawaited(
          AiCostTracker.event(
            feature: 'lesson_audio_deck',
            event: 'deck_retry_wave_started',
            requestId: story.id,
            extra: {
              'lesson_id': story.id,
              'retry_segment_count': pending.length,
              'worker_count': workerCount,
            },
          ),
        );
      }
      attempt++;
    }
    final complete = pending.isEmpty;
    unawaited(
      AiCostTracker.event(
        feature: 'lesson_audio_deck',
        event: 'deck_prepare_finished',
        requestId: story.id,
        extra: {
          'lesson_id': story.id,
          'segment_count': story.passage.segments.length,
          'complete': complete,
          'worker_count': workerCount,
          'attempts': attempt - 1,
          'failed_segments': pending,
        },
      ),
    );
    return complete;
  }

  Future<bool> _prepareSegment({
    required GeneratedStory story,
    required CommonDatabase db,
    required int index,
    required String voiceName,
    int attempt = 1,
  }) async {
    final text = story.passage.segments[index].fr.trim();
    final cacheKey = GeminiLiveAudioService.cacheKeyFor(
      text: text,
      voiceName: voiceName,
    );
    if (text.isEmpty) return false;
    unawaited(
      AiCostTracker.event(
        feature: 'lesson_audio_deck',
        event: 'deck_segment_started',
        requestId: '${story.id}:$index',
        extra: {
          'lesson_id': story.id,
          'segment_index': index,
          'attempt': attempt,
        },
      ),
    );
    try {
      // generateAndCache owns the single local -> remote -> Live resolution
      // path. Calling loadCached first duplicated the remote Storage lookup
      // on every miss, which could add two timeout windows before the first
      // sentence was rendered.
      final bytes = await GeminiLiveAudioService.shared.generateAndCache(
        text: text,
        contentItemId: story.segmentContentId(index),
        voiceName: voiceName,
      );
      if (bytes == null || bytes.isEmpty || bytes.length.isOdd) {
        _upsert(
          db: db,
          story: story,
          index: index,
          text: text,
          voiceName: voiceName,
          cacheKey: cacheKey,
          status: 'failed',
        );
        unawaited(
          AiCostTracker.event(
            feature: 'lesson_audio_deck',
            event: 'deck_segment_failed',
            requestId: '${story.id}:$index',
            extra: {
              'lesson_id': story.id,
              'segment_index': index,
              'attempt': attempt,
            },
          ),
        );
        return false;
      }
      await GeminiLiveAudioService.shared.ensureRemote(
        text: text,
        contentItemId: story.segmentContentId(index),
        voiceName: voiceName,
        bytes: bytes,
      );
      _upsert(
        db: db,
        story: story,
        index: index,
        text: text,
        voiceName: voiceName,
        cacheKey: cacheKey,
        status: 'local_ready',
      );
      unawaited(
        AiCostTracker.event(
          feature: 'lesson_audio_deck',
          event: 'deck_segment_ready',
          requestId: '${story.id}:$index',
          extra: {
            'lesson_id': story.id,
            'segment_index': index,
            'pcm_bytes': bytes.length,
            'attempt': attempt,
          },
        ),
      );
      return true;
    } catch (_) {
      _upsert(
        db: db,
        story: story,
        index: index,
        text: text,
        voiceName: voiceName,
        cacheKey: cacheKey,
        status: 'failed',
      );
      unawaited(
        AiCostTracker.event(
          feature: 'lesson_audio_deck',
          event: 'deck_segment_exception',
          requestId: '${story.id}:$index',
          extra: {
            'lesson_id': story.id,
            'segment_index': index,
            'attempt': attempt,
          },
        ),
      );
      return false;
    }
  }

  void _upsert({
    required CommonDatabase db,
    required GeneratedStory story,
    required int index,
    required String text,
    required String voiceName,
    required String cacheKey,
    required String status,
  }) {
    db.execute(
      '''INSERT INTO lesson_audio_decks
         (lesson_id, segment_index, spoken_text, voice_name, cache_key,
          status, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(lesson_id, segment_index) DO UPDATE SET
           spoken_text = excluded.spoken_text,
           voice_name = excluded.voice_name,
           cache_key = excluded.cache_key,
           status = excluded.status,
           updated_at = excluded.updated_at''',
      [
        story.id,
        index,
        text,
        voiceName,
        cacheKey,
        status,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }
}
