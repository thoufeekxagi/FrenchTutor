import 'dart:async';

import '../models/content_models.dart';
import '../models/tutor_persona.dart';
import 'gemini_live_audio_service.dart';
import 'listening_audio_prefetch_cache.dart';
import 'sync_service.dart';

/// Warms durable lesson assets after the library has rendered.
///
/// This service deliberately reads only assets that already exist. It never
/// starts generation, so opening a library cannot consume an LLM quota or
/// compete with a lesson the learner is currently using.
class RecentLessonWarmupService {
  RecentLessonWarmupService._();

  static final shared = RecentLessonWarmupService._();

  static const _maxStories = 15;
  static const _maxConcurrent = 3;
  final Set<String> _inFlight = <String>{};

  void warm({
    required List<GeneratedStory> stories,
    required SyncService sync,
  }) {
    final selected = stories.take(_maxStories).toList(growable: false);
    if (selected.isEmpty) return;
    unawaited(_warmQueue(selected, sync));
  }

  Future<void> _warmQueue(
    List<GeneratedStory> stories,
    SyncService sync,
  ) async {
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= stories.length) return;
        final story = stories[cursor++];
        if (story.practiceMode == 'listening') {
          await _warmListening(story, sync);
        } else if (story.practiceMode == 'reading') {
          await _warmReading(story);
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(_maxConcurrent, (_) => worker()),
    );
  }

  Future<void> _warmListening(GeneratedStory story, SyncService sync) async {
    final key = 'listening:${story.id}';
    if (!_inFlight.add(key)) return;
    try {
      await ListeningAudioPrefetchCache.shared.prefetch(
        story: story,
        sync: sync,
      );
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> _warmReading(GeneratedStory story) async {
    final segments = story.passage.segments.take(2);
    for (var index = 0; index < segments.length; index++) {
      final text = segments.elementAt(index).fr;
      final key = 'reading:${story.id}:$index';
      if (!_inFlight.add(key)) continue;
      try {
        await GeminiLiveAudioService.shared.loadCached(
          text: text,
          voiceName: ActiveTutor.current.voiceName,
        );
      } finally {
        _inFlight.remove(key);
      }
    }
  }
}
