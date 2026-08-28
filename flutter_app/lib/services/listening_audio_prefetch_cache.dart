import 'dart:async';

import 'elevenlabs_audio_service.dart';
import 'sync_service.dart';
import '../models/content_models.dart';

/// Keeps a very small in-memory deck of the most recent saved Listening clips.
///
/// The story row and audio path remain durable in Supabase/SQLite. This cache
/// only removes the repeated private-storage download when a learner opens one
/// of the latest lessons during the current app session.
class ListeningAudioPrefetchCache {
  ListeningAudioPrefetchCache._();

  static final shared = ListeningAudioPrefetchCache._();

  static const _capacity = 3;
  final Map<String, Future<ElevenLabsAudioClip?>> _entries = {};
  final List<String> _recency = [];

  Future<ElevenLabsAudioClip?>? peek(String storyId) => _entries[storyId];

  Future<ElevenLabsAudioClip?> prefetch({
    required GeneratedStory story,
    required SyncService sync,
  }) {
    final path = story.audioPath?.trim() ?? '';
    if (path.isEmpty) return Future<ElevenLabsAudioClip?>.value(null);

    final existing = _entries[story.id];
    if (existing != null) {
      _touch(story.id);
      return existing;
    }

    final future = _download(story: story, path: path, sync: sync);
    _entries[story.id] = future;
    _touch(story.id);
    _trim();
    unawaited(
      future.then<void>(
        (_) {},
        onError: (_, _) {
          _entries.remove(story.id);
          _recency.remove(story.id);
        },
      ),
    );
    return future;
  }

  Future<ElevenLabsAudioClip?> _download({
    required GeneratedStory story,
    required String path,
    required SyncService sync,
  }) async {
    try {
      final bytes = await sync.downloadListeningAudio(path);
      if (bytes == null || bytes.isEmpty) return null;
      final mode = story.audioMode?.trim().isNotEmpty == true
          ? story.audioMode!.trim()
          : 'narration';
      final isWav =
          path.toLowerCase().endsWith('.wav') || mode == 'gemini_live_spoken';
      return ElevenLabsAudioClip(
        mode: mode,
        bytes: bytes,
        container: isWav ? 'wav' : 'mp3',
      );
    } catch (_) {
      return null;
    }
  }

  void _touch(String storyId) {
    _recency.remove(storyId);
    _recency.add(storyId);
  }

  void _trim() {
    while (_recency.length > _capacity) {
      final oldest = _recency.removeAt(0);
      _entries.remove(oldest);
    }
  }
}
