import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<List<V3Lesson>> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final index =
        jsonDecode(await b.loadString(indexPath)) as Map<String, dynamic>;
    final files = (index['lessons'] as List? ?? const []).cast<String>();
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

/// Which authored lessons the learner has finished, and where they stopped in
/// the one they left half way. Local to this device.
abstract final class V3Progress {
  static String get _doneKey => v3Key('v3_completed_lessons');
  static String get _posKey => v3Key('v3_lesson_position');

  static Future<Set<String>> completed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_doneKey) ?? const []).toSet();
  }

  static Future<void> markDone(String lessonId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_doneKey) ?? const []).toSet()
      ..add(lessonId);
    await prefs.setStringList(_doneKey, set.toList());
    await savePosition(lessonId, 0);
  }

  /// Step to resume from, by lesson id. Missing or zero means start at the top.
  static Future<Map<String, int>> positions() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, int>{};
    for (final entry in prefs.getStringList(_posKey) ?? const <String>[]) {
      final i = entry.lastIndexOf(':');
      if (i < 0) continue;
      final n = int.tryParse(entry.substring(i + 1));
      if (n != null && n > 0) out[entry.substring(0, i)] = n;
    }
    return out;
  }

  static Future<void> savePosition(String lessonId, int step) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await positions();
    if (step > 0) {
      map[lessonId] = step;
    } else {
      map.remove(lessonId);
    }
    await prefs.setStringList(_posKey, [
      for (final e in map.entries) '${e.key}:${e.value}',
    ]);
  }
}
