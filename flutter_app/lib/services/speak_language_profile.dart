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
    required this.tutorTurnWordLimit,
    required this.newWordsPerTurn,
    required this.levelContract,
  });

  final String level;
  final int englishPercent;
  final int frenchPercent;
  final String shortLabel;
  final String roadmapHint;
  final String sessionHint;

  /// Hard limits for the live speaking contract. These are intentionally
  /// concrete: a label such as "beginner" is not enough to stop a model from
  /// producing an advanced prompt in an A1 session.
  final String tutorTurnWordLimit;
  final int newWordsPerTurn;
  final String levelContract;

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
        tutorTurnWordLimit: '5–9 words',
        newWordsPerTurn: 2,
        levelContract:
            'Use concrete everyday situations, short present-tense sentences, '
            'and one follow-up at a time. Avoid idioms, abstract debate, and '
            'long subordinate clauses. Offer a brief English cue only when '
            'the learner is blocked.',
      ),
      'B1' || 'CONVERSATIONAL' => const SpeakLanguageProfile._(
        level: 'B1',
        englishPercent: 40,
        frenchPercent: 60,
        shortLabel: 'French-led',
        roadmapHint: 'French practice · English when useful',
        sessionHint:
            'Work in French first; use the English cue only when you need it.',
        tutorTurnWordLimit: '8–14 words',
        newWordsPerTurn: 4,
        levelContract:
            'Use natural everyday French with connected sentences, practical '
            'past and future references, and one meaningful follow-up. Do not '
            'translate automatically; clarify only when needed.',
      ),
      'B2' => const SpeakLanguageProfile._(
        level: 'B2',
        englishPercent: 20,
        frenchPercent: 80,
        shortLabel: 'Immersive French',
        roadmapHint: 'Immersive French · English when needed',
        sessionHint:
            'Stay in French and use the English cue only to unblock yourself.',
        tutorTurnWordLimit: '10–18 words',
        newWordsPerTurn: 6,
        levelContract:
            'Use mostly French with natural connected turns, opinions, '
            'reasons, and occasional nuance. Expect independent answers and '
            'repair after the learner finishes speaking.',
      ),
      _ => const SpeakLanguageProfile._(
        level: 'A1',
        englishPercent: 85,
        frenchPercent: 15,
        shortLabel: 'English-led',
        roadmapHint: 'English-led · French practice',
        sessionHint:
            'Understand the explanation in English, then try one small French step.',
        tutorTurnWordLimit: '3–6 words',
        newWordsPerTurn: 1,
        levelContract:
            'Assume a true beginner. Use familiar concrete nouns and simple '
            'present-tense phrases. Model before asking the learner to speak, '
            'keep one idea per turn, and give a short English gloss for new '
            'French. Never introduce advanced idioms, abstract topics, or '
            'multi-clause questions.',
      ),
    };
  }

  static SpeakLanguageProfile forProfile(Profile profile) =>
      forLevel(profile.level);
}
