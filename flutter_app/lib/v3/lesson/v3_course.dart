import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/learning_store.dart';
import '../v3_prefs.dart';
import 'v3_lesson.dart';

/// The authored course: an ordered list of lesson files bundled with the app.
///
/// `assets/content/tcf/course.json` lists the lesson files in order:
/// `{"lessons": ["s0-01.json", "a1-u01-words-a.json"]}`. Each file lives in
/// `assets/content/tcf/lessons/`. Dev-only lessons (`"dev": true`) are hidden in
/// release builds.
abstract final class V3Course {
  static const indexPath = 'assets/content/tcf/course.json';
  static const lessonDir = 'assets/content/tcf/lessons/';

  static Future<List<V3Lesson>> load({
    AssetBundle? bundle,
    List<String> idPrefixes = const [],
  }) async {
    final b = bundle ?? rootBundle;
    final index =
        jsonDecode(await b.loadString(indexPath)) as Map<String, dynamic>;
    final indexedFiles = (index['lessons'] as List? ?? const []).cast<String>();
    final files = idPrefixes.isEmpty
        ? indexedFiles
        : indexedFiles
              .where(
                (file) => idPrefixes.any(
                  (prefix) => file
                      .replaceFirst(RegExp(r'\.json$'), '')
                      .startsWith(prefix),
                ),
              )
              .toList();
    final lessons = <V3Lesson>[];
    for (final file in files) {
      try {
        final raw = jsonDecode(await b.loadString('$lessonDir$file'));
        final lesson = V3Lesson.fromJson(raw as Map<String, dynamic>);
        if (lesson.dev && !kDebugMode) continue;
        lessons.add(lesson);
      } catch (error) {
        // A broken lesson must be loud while authoring and harmless in release.
        debugPrint('V3Course: could not load $file: $error');
        if (kDebugMode) rethrow;
      }
    }
    return lessons;
  }
}

/// Real progress, kept apart from where the learner is looking.
///
/// - **completed**: lessons finished.
/// - **frontier** (`positions`): the furthest step reached in a lesson that is
///   not finished. It only ever moves forward. Going back to review, replaying,
///   or reopening never lowers it, so Resume always means "where I really got
///   to".
/// - **active**: the unfinished lesson the learner last moved forward in.
/// - **lastCompleted**: the lesson finished most recently, so the path carries
///   on from there.
///
/// SQLite is the local source of truth and SyncService mirrors it to the
/// signed-in learner. SharedPreferences remain a compatibility import for
/// progress written by earlier V3 builds and an isolated E2E sandbox.
abstract final class V3Progress {
  static String get _doneKey => v3Key('v3_completed_lessons');
  static String get _posKey => v3Key('v3_lesson_position');
  static String get _activeKey => v3Key('v3_last_active_lesson');
  static String get _lastDoneKey => v3Key('v3_last_completed_lesson');

  static bool get _isolatedE2E =>
      kDebugMode && const bool.fromEnvironment('E2E_SHELL');

  static Future<void> importLegacyPreferences(LearningStore store) async {
    if (_isolatedE2E) return;
    final prefs = await SharedPreferences.getInstance();
    final completed = (prefs.getStringList(_doneKey) ?? const []).toSet();
    final positions = await _readPreferencePositions(prefs);
    for (final lessonId in completed) {
      store.saveV3CourseProgress(lessonId, currentStep: 0, completed: true);
    }
    for (final entry in positions.entries) {
      if (completed.contains(entry.key)) continue;
      store.saveV3CourseProgress(
        entry.key,
        currentStep: entry.value,
        completed: false,
      );
    }
  }

  static Future<Set<String>> completed({LearningStore? store}) async {
    final prefs = await SharedPreferences.getInstance();
    final result = (prefs.getStringList(_doneKey) ?? const []).toSet();
    if (store != null && !_isolatedE2E) {
      for (final entry in store.v3CourseProgress().values) {
        if (entry.status == 'completed') result.add(entry.lessonId);
      }
    }
    return result;
  }

  // Every change is a read, change, write. Two quick ones must never
  // interleave, or the later write could undo the earlier one.
  static Future<void> _tail = Future<void>.value();
  static Future<void> _serial(Future<void> Function() change) {
    final next = _tail.then((_) => change());
    _tail = next.catchError((_) {});
    return next;
  }

  /// Tests run each case in its own fake-time zone; a write left unfinished by
  /// one case must not hold up the next.
  @visibleForTesting
  static void resetQueueForTest() => _tail = Future<void>.value();

  static Future<String?> lastActive({LearningStore? store}) async {
    if (store != null && !_isolatedE2E) {
      final saved = store.lastV3ActiveLesson();
      if (saved != null) return saved;
    }
    return (await SharedPreferences.getInstance()).getString(_activeKey);
  }

  static Future<String?> lastCompleted({LearningStore? store}) async {
    if (store != null && !_isolatedE2E) {
      final saved = store.lastV3CompletedLesson();
      if (saved != null) return saved;
    }
    return (await SharedPreferences.getInstance()).getString(_lastDoneKey);
  }

  static Future<void> markDone(String lessonId, {LearningStore? store}) =>
      _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final set = (prefs.getStringList(_doneKey) ?? const []).toSet();
        final firstTime = set.add(lessonId);
        await prefs.setStringList(_doneKey, set.toList());
        await _savePosition(lessonId, 0);
        if (store != null && !_isolatedE2E) {
          store.saveV3CourseProgress(lessonId, currentStep: 0, completed: true);
        }
        // Replaying a finished lesson must not move the path.
        if (firstTime) await prefs.setString(_lastDoneKey, lessonId);
        if (prefs.getString(_activeKey) == lessonId) {
          await prefs.remove(_activeKey);
        }
      });

  /// Furthest step reached, by lesson id. Missing means nothing real yet.
  static Future<Map<String, int>> positions({LearningStore? store}) async {
    final prefs = await SharedPreferences.getInstance();
    final out = await _readPreferencePositions(prefs);
    if (store != null && !_isolatedE2E) {
      for (final entry in store.v3CourseProgress().values) {
        if (entry.status == 'completed') {
          out.remove(entry.lessonId);
        } else if (entry.currentStep > (out[entry.lessonId] ?? 0)) {
          out[entry.lessonId] = entry.currentStep;
        }
      }
    }
    return out;
  }

  static Future<Map<String, int>> _readPreferencePositions(
    SharedPreferences prefs,
  ) async {
    final out = <String, int>{};
    for (final entry in prefs.getStringList(_posKey) ?? const <String>[]) {
      final i = entry.lastIndexOf(':');
      if (i < 0) continue;
      final n = int.tryParse(entry.substring(i + 1));
      if (n != null && n > 0) out[entry.substring(0, i)] = n;
    }
    return out;
  }

  /// The learner moved forward to [step]. Only moves progress forward, never
  /// for a finished lesson (a replay is practice, not progress).
  static Future<void> advanceFrontier(
    String lessonId,
    int step, {
    LearningStore? store,
  }) => _serial(() async {
    if (step <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getStringList(_doneKey) ?? const []).contains(lessonId)) {
      return;
    }
    if (store != null &&
        !_isolatedE2E &&
        store.v3CourseProgress()[lessonId]?.status == 'completed') {
      return;
    }
    final map = await positions();
    if ((map[lessonId] ?? 0) < step) {
      map[lessonId] = step;
      await _write(prefs, map);
    }
    await prefs.setString(_activeKey, lessonId);
    if (store != null && !_isolatedE2E) {
      store.saveV3CourseProgress(lessonId, currentStep: step, completed: false);
    }
  });

  /// Raw write. Prefer [advanceFrontier]; this exists so finishing a lesson can
  /// clear its position.
  static Future<void> savePosition(
    String lessonId,
    int step, {
    LearningStore? store,
  }) => _serial(() => _savePosition(lessonId, step, store: store));

  static Future<void> _savePosition(
    String lessonId,
    int step, {
    LearningStore? store,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await positions();
    if (step > 0) {
      map[lessonId] = step;
    } else {
      map.remove(lessonId);
    }
    await _write(prefs, map);
    if (step > 0 && store != null && !_isolatedE2E) {
      store.saveV3CourseProgress(lessonId, currentStep: step, completed: false);
    }
  }

  static Future<void> _write(SharedPreferences prefs, Map<String, int> map) =>
      prefs.setStringList(_posKey, [
        for (final e in map.entries) '${e.key}:${e.value}',
      ]);

  /// The one lesson the Learn tab offers as "next".
  ///
  /// 1. The unfinished lesson the learner last moved forward in.
  /// 2. Otherwise the first unfinished lesson after the one finished last, so
  ///    the path flows on from where they are.
  /// 3. Otherwise the first unfinished lesson anywhere.
  static V3Lesson? pickNext(
    List<V3Lesson> course,
    Set<String> done,
    Map<String, int> frontier, {
    String? active,
    String? lastCompleted,
  }) {
    if (active != null &&
        !done.contains(active) &&
        (frontier[active] ?? 0) > 0) {
      for (final l in course) {
        if (l.id == active) return l;
      }
    }
    final from = lastCompleted == null
        ? -1
        : course.indexWhere((l) => l.id == lastCompleted);
    for (var i = from + 1; i < course.length; i++) {
      if (!done.contains(course[i].id)) return course[i];
    }
    for (final l in course) {
      if (!done.contains(l.id)) return l;
    }
    return null;
  }
}
