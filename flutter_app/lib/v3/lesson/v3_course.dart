import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

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

/// Which authored lessons the learner has finished. Local and independent of
/// the legacy adaptive plan.
abstract final class V3Progress {
  static const _key = 'v3_completed_lessons';

  static Future<Set<String>> completed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  static Future<void> markDone(String lessonId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_key) ?? const []).toSet()..add(lessonId);
    await prefs.setStringList(_key, set.toList());
  }
}
