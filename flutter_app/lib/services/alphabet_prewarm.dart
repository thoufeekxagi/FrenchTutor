import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/alphabet_data.dart';
import '../models/tutor_persona.dart';
import 'lesson_speech_service.dart';

/// Seeds the selected tutor's complete bundled alphabet catalog in the
/// background. There are 31 short PCM clips (26 letters + 5 accents), roughly
/// 1–2 MB per tutor, so we never copy all four voices onto every device.
class AlphabetPrewarm {
  AlphabetPrewarm._();

  static const _prefsKeyPrefix = 'alphabet_prewarm_bundled_v2_';
  static const _cacheNamespace = 'alphabet-bundled-v2';
  static final Set<String> _inFlight = {};

  static Future<void> maybeStart({
    required bool isBeginner,
    TutorPersona? tutor,
  }) async {
    if (!isBeginner) return;
    final selectedTutor = tutor ?? ActiveTutor.current;
    if (_inFlight.contains(selectedTutor.id)) return;
    final prefs = await _prefs();
    final prefsKey = '$_prefsKeyPrefix${selectedTutor.id}';
    if (prefs == null || (prefs.getBool(prefsKey) ?? false)) return;

    _inFlight.add(selectedTutor.id);
    unawaited(() async {
      try {
        final items = alphabetPrewarmItems(persona: selectedTutor);
        final seeded = await LessonSpeechService.shared.prewarmBundled(
          items,
          // Two workers keep A/B moving together without opening a burst of
          // native audio work or competing with a live tutor session.
          concurrency: 2,
          cacheNamespace: _cacheNamespace,
        );
        if (seeded == items.length) await prefs.setBool(prefsKey, true);
      } catch (e) {
        // The bundled assets remain available for direct loading on the
        // alphabet screen, so a background seed failure is not fatal.
        debugPrint('AlphabetPrewarm: bundled seed failed: $e');
      } finally {
        _inFlight.remove(selectedTutor.id);
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
