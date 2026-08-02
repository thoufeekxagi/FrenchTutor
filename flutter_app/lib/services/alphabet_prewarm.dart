import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/alphabet_data.dart';
import 'lesson_speech_service.dart';

/// Fires once, right when onboarding finishes and both the learner's level
/// and their chosen tutor voice are known, so every alphabet/accent sound
/// is already synthesized and cached by the time a brand-new beginner
/// actually opens "Learn the Alphabet" — instead of only starting the
/// prewarm once they're already sitting on that screen waiting on it.
///
/// Only worth doing for a true beginner (A1): nobody past that level is
/// likely to ever open this lesson, so there's no reason to spend Gemini
/// calls warming it for them. Guarded so it only ever runs once per
/// install — a rerun would just be a wasted synchronous cache-hit sweep
/// (harmless), not a correctness bug, but there's no reason to repeat it.
class AlphabetPrewarm {
  AlphabetPrewarm._();

  static const _prefsKey = 'alphabet_prewarm_started_v1';

  static Future<void> maybeStart({required bool isBeginner}) async {
    if (!isBeginner) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) ?? false) return;
      // Marked before the work even starts, not after it completes — this
      // is a "run once ever" gate, not a completion flag. If the app is
      // killed mid-prewarm, whatever didn't finish just falls back to the
      // same on-demand generate-on-tap path every other screen already
      // has; it's a lost head start, not a broken feature.
      await prefs.setBool(_prefsKey, true);
    } catch (e) {
      debugPrint('AlphabetPrewarm: prefs unavailable, skipping: $e');
      return;
    }
    unawaited(
      LessonSpeechService.shared.prewarmNarrationBounded(
        alphabetPrewarmItems(),
      ),
    );
  }
}
