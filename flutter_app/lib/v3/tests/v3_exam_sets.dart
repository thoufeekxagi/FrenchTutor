import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../lesson/v3_lesson.dart';

/// The simple TCF Canada practice sets: four formats at each of A1 to B2.
/// Each set is one authored lesson in `assets/content/tcf/exams/`, played in
/// the normal lesson player. They use general content and teach the format;
/// full timed mocks come later.
abstract final class V3ExamSets {
  static const levels = ['a1', 'a2', 'b1', 'b2'];
  static const skills = ['listening', 'reading', 'writing', 'speaking'];

  static String assetPath(String level, String skill) =>
      'assets/content/tcf/exams/${level.toLowerCase()}_$skill.json';

  static Future<V3Lesson> load(String level, String skill) async {
    final raw = jsonDecode(
      await rootBundle.loadString(assetPath(level, skill)),
    );
    return V3Lesson.fromJson((raw as Map).cast<String, dynamic>());
  }
}
