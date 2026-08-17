import '../models/profile.dart';

/// Copy and teaching guidance for the published Speak-style course.
///
/// The catalog keeps French as the learning material, while this profile
/// controls the amount of English scaffolding shown around it. It is used by
/// the UI as well as the authoring prompt so a learner never gets an
/// immersion-heavy course by accident.
class SpeakLanguageProfile {
  const SpeakLanguageProfile._({
    required this.level,
    required this.englishPercent,
    required this.frenchPercent,
    required this.shortLabel,
    required this.roadmapHint,
    required this.sessionHint,
  });

  final String level;
  final int englishPercent;
  final int frenchPercent;
  final String shortLabel;
  final String roadmapHint;
  final String sessionHint;

  bool get isBeginner => level == 'A1' || level == 'A2';

  static SpeakLanguageProfile forLevel(String rawLevel) {
    final level = rawLevel.trim().toUpperCase();
    return switch (level) {
      'A2' => const SpeakLanguageProfile._(
        level: 'A2',
        englishPercent: 60,
        frenchPercent: 40,
        shortLabel: 'Guided balance',
        roadmapHint: 'English support · French practice',
        sessionHint:
            'Read the guidance in English, then use the French phrase.',
      ),
      'B1' || 'CONVERSATIONAL' => const SpeakLanguageProfile._(
        level: 'B1',
        englishPercent: 40,
        frenchPercent: 60,
        shortLabel: 'French-led',
        roadmapHint: 'French practice · English when useful',
        sessionHint:
            'Work in French first; use the English cue only when you need it.',
      ),
      'B2' => const SpeakLanguageProfile._(
        level: 'B2',
        englishPercent: 20,
        frenchPercent: 80,
        shortLabel: 'Immersive French',
        roadmapHint: 'Immersive French · English when needed',
        sessionHint:
            'Stay in French and use the English cue only to unblock yourself.',
      ),
      _ => const SpeakLanguageProfile._(
        level: 'A1',
        englishPercent: 85,
        frenchPercent: 15,
        shortLabel: 'English-led',
        roadmapHint: 'English-led · French practice',
        sessionHint:
            'Understand the explanation in English, then try one small French step.',
      ),
    };
  }

  static SpeakLanguageProfile forProfile(Profile profile) =>
      forLevel(profile.level);
}
