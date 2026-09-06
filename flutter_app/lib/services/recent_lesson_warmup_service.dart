import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/content_models.dart';
import '../data/database/generated_story_store.dart';
import 'lesson_asset_prefetch_service.dart';
import 'sync_service.dart';

/// Warms durable lesson assets after the library has rendered.
///
/// Existing local/Supabase assets are reused first. Missing starter assets
/// are prepared through the same Gemini renderer used by the lesson itself,
/// one lesson at a time, so background warming cannot create a quota burst.
class RecentLessonWarmupService {
  RecentLessonWarmupService._();

  static final shared = RecentLessonWarmupService._();

  static const _maxStories = 15;
  // Each narration deck already uses a bounded three-item worker pool. Keep
  // lesson-level work serial so five starter lessons cannot multiply that
  // into a burst of sockets and hit Gemini's realtime quota.
  static const _maxConcurrent = 1;
  final Set<String> _inFlight = <String>{};

  void warm({
    required List<GeneratedStory> stories,
    required SyncService sync,
    GeneratedStoryStore? storyStore,
  }) {
    final selected = stories.take(_maxStories).toList(growable: false);
    if (selected.isEmpty) return;
    unawaited(_warmQueue(selected, sync, storyStore));
  }

  Future<void> _warmQueue(
    List<GeneratedStory> stories,
    SyncService sync,
    GeneratedStoryStore? storyStore,
  ) async {
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= stories.length) return;
        final story = stories[cursor++];
        try {
          if (story.practiceMode == 'listening') {
            await _warmListening(story, sync, storyStore);
          } else if (story.practiceMode == 'reading') {
            await _warmReading(story);
          }
        } catch (error) {
          // Prefetch is an optimization. The opened screen can retry the same
          // shared operation and show an actionable error if it still fails.
          debugPrint('Lesson asset warm-up skipped for ${story.id}: $error');
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(_maxConcurrent, (_) => worker()),
    );
  }

  Future<void> _warmListening(
    GeneratedStory story,
    SyncService sync,
    GeneratedStoryStore? storyStore,
  ) async {
    final key = 'listening:${story.id}';
    if (!_inFlight.add(key)) return;
    try {
      await LessonAssetPrefetchService.shared.prefetchListening(
        story: story,
        sync: sync,
        storyStore: storyStore,
      );
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> _warmReading(GeneratedStory story) async {
    final key = 'reading:${story.id}';
    if (!_inFlight.add(key)) return;
    try {
      await LessonAssetPrefetchService.shared.prefetchNarration(story);
    } finally {
      _inFlight.remove(key);
    }
  }
}
