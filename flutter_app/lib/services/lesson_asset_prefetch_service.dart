import 'dart:async';
import 'dart:typed_data';

import '../data/database/generated_story_store.dart';
import '../models/content_models.dart';
import '../models/tutor_persona.dart';
import 'audio_container_utils.dart';
import 'elevenlabs_audio_service.dart';
import 'gemini_live_audio_service.dart';
import 'listening_audio_prefetch_cache.dart';
import 'sync_service.dart';

/// One entry point for preparing lesson audio before the learner needs it.
///
/// Reading-style lessons resolve every sentence into the shared persistent
/// PCM cache. Listening lessons download their durable Supabase clip, or make
/// and upload it once when an older/starter row does not have an audio path.
/// In-flight work is shared so library warming, screen opening, and a play tap
/// can never start duplicate downloads or Gemini renders.
class LessonAssetPrefetchService {
  LessonAssetPrefetchService._();

  static final shared = LessonAssetPrefetchService._();

  final Map<String, Future<ElevenLabsAudioClip?>> _listeningInFlight = {};
  final Map<String, Future<void>> _narrationInFlight = {};
  final Map<String, DateTime> _narrationLastAttemptAt = {};

  // Course's roadmap calls this on every single background refresh pass for
  // every ready Listening lesson, with no caller-side throttling — that is
  // by design (see speak_roadmap_screen.dart's _prefetchUpcomingListeningAudio),
  // so this method itself must be the thing that makes repeated calls cheap.
  // Without in-flight/cooldown protection here, a persistently failing
  // Gemini Live socket (bad token, quota, connectivity) turned every single
  // refresh pass into a fresh full-deck retry storm instead of one bounded
  // attempt every couple of minutes. warmDeck swallows every individual
  // clip's error internally (it always resolves, never rejects), so the
  // cooldown below is keyed on "an attempt just ran" rather than on failure —
  // a successful attempt is harmless to skip too, since its clips are
  // already cached and any real cache miss just waits for the next window.
  static const _narrationRetryCooldown = Duration(minutes: 2);

  Future<void> prefetchNarration(GeneratedStory story) {
    final key = story.id;
    final existing = _narrationInFlight[key];
    if (existing != null) return existing;
    final lastAttempt = _narrationLastAttemptAt[key];
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < _narrationRetryCooldown) {
      return Future<void>.value();
    }
    final items = <({String text, String contentItemId})>[
      for (var index = 0; index < story.passage.segments.length; index++)
        (
          text: story.passage.segments[index].fr,
          contentItemId: story.segmentContentId(index),
        ),
      for (final keyword in story.keywords)
        (text: keyword.fr, contentItemId: '${story.id}_kw_${keyword.id}'),
    ];
    if (items.isEmpty) return Future<void>.value();
    _narrationLastAttemptAt[key] = DateTime.now();
    final operation = GeminiLiveAudioService.shared.warmDeck(
      items: items,
      voiceName: ActiveTutor.current.voiceName,
    );
    _narrationInFlight[key] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_narrationInFlight[key], operation)) {
          _narrationInFlight.remove(key);
        }
      }),
    );
    return operation;
  }

  Future<ElevenLabsAudioClip?> prefetchListening({
    required GeneratedStory story,
    required SyncService sync,
    GeneratedStoryStore? storyStore,
  }) {
    // The full Listening track is one durable WAV, while focus/dictation
    // controls play individual lines. Warm those line clips through the same
    // universal PCM cache at the same time as the full track is prepared.
    unawaited(
      prefetchNarration(story).catchError((_) {
        // Full-track preparation remains independent and authoritative.
      }),
    );
    final path = story.audioPath?.trim() ?? '';
    final key = '${story.id}|$path';
    final existing = _listeningInFlight[key];
    if (existing != null) return existing;
    final operation = _prefetchListeningUnshared(
      story: story,
      sync: sync,
      storyStore: storyStore,
    );
    _listeningInFlight[key] = operation;
    void clear() {
      if (identical(_listeningInFlight[key], operation)) {
        _listeningInFlight.remove(key);
      }
    }

    unawaited(operation.then<void>((_) => clear(), onError: (_, _) => clear()));
    return operation;
  }

  Future<ElevenLabsAudioClip?> _prefetchListeningUnshared({
    required GeneratedStory story,
    required SyncService sync,
    GeneratedStoryStore? storyStore,
  }) async {
    final path = story.audioPath?.trim() ?? '';
    if (path.isNotEmpty) {
      return ListeningAudioPrefetchCache.shared.prefetch(
        story: story,
        sync: sync,
      );
    }

    final narration = story.passage.fullText.trim().isNotEmpty
        ? story.passage.fullText.trim()
        : story.passage.segments.map((segment) => segment.fr).join(' ');
    if (narration.trim().isEmpty) return null;
    final pcm = await GeminiLiveAudioService.shared.synthesizeListeningLesson(
      text: narration,
      format: 'narration',
      level: story.levelBand,
    );
    final wav = pcm16ToWav(
      pcm,
      sampleRate: GeminiLiveAudioService.outputSampleRateHz,
    );
    final uploadedPath = await sync.uploadListeningAudio(
      storyId: story.id,
      mode: 'gemini_live_spoken',
      bytes: wav,
      extension: 'wav',
      contentType: 'audio/wav',
    );
    if (uploadedPath?.isNotEmpty == true) {
      final persistedStory = story.copyWith(
        audioPath: uploadedPath,
        audioMode: 'gemini_live_spoken',
      );
      storyStore?.updateAudio(
        storyId: story.id,
        audioPath: uploadedPath!,
        audioMode: 'gemini_live_spoken',
      );
      final clip = ElevenLabsAudioClip(
        mode: 'gemini_live_spoken',
        bytes: Uint8List.fromList(wav),
        container: 'wav',
      );
      await ListeningAudioPrefetchCache.shared.remember(
        story: persistedStory,
        clip: clip,
      );
      return clip;
    }
    return ElevenLabsAudioClip(
      mode: 'gemini_live_spoken',
      bytes: Uint8List.fromList(wav),
      container: 'wav',
    );
  }
}
