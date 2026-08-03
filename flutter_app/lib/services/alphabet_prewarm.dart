import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/alphabet_data.dart';
import 'lesson_speech_service.dart';

/// Seeds the complete bundled alphabet catalog right when onboarding finishes
/// and both the learner's level and chosen tutor voice are known. The catalog
/// contains all 26 letters, five accents, and all four tutor voices, so a
/// voice change never needs a Gemini request.
///
/// Only worth doing for a true beginner (A1): nobody past that level is likely
/// to open this lesson, and the assets remain available as a deterministic
/// fallback if the background copy is interrupted.
class AlphabetPrewarm {
  AlphabetPrewarm._();

  static const _prefsKey = 'alphabet_prewarm_bundled_v1';

  static Future<void> maybeStart({required bool isBeginner}) async {
    if (!isBeginner) return;
    final prefs = await _prefs();
    if (prefs == null || (prefs.getBool(_prefsKey) ?? false)) return;

    unawaited(() async {
      try {
        final items = alphabetPrewarmItems();
        final seeded = await LessonSpeechService.shared.prewarmBundled(items);
        if (seeded == items.length) await prefs.setBool(_prefsKey, true);
      } catch (e) {
        // The bundled assets remain available for direct loading on the
        // alphabet screen, so a background seed failure is not fatal.
        debugPrint('AlphabetPrewarm: bundled seed failed: $e');
      }
    }());
  }

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('AlphabetPrewarm: prefs unavailable, skipping: $e');
      return null;
    }
  }
}
