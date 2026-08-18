import '../models/content_models.dart';

/// Keeps vocabulary selection conservative when a learner is still building
/// a basic lexicon. The bundled phases are ordered by difficulty, but a raw
/// flatten of all phases is unsafe: an A1 learner must never receive B1/B2
/// exam, abstract, or formal-letter vocabulary just because it exists locally.
abstract final class VocabularyLevelPolicy {
  static int rank(String rawLevel) => switch (rawLevel.trim().toLowerCase()) {
    'a1' || 'zero' || 'basics' || 'unsure' => 1,
    'a2' => 2,
    'b1' || 'conversational' => 3,
    'b2' => 4,
    _ => 1,
  };

  static String normalise(String rawLevel) => switch (rank(rawLevel)) {
    1 => 'A1',
    2 => 'A2',
    3 => 'B1',
    _ => 'B2',
  };

  static int maxBundledPhase(String rawLevel) => switch (rank(rawLevel)) {
    1 => 1,
    2 => 2,
    _ => 3,
  };

  static List<VocabPhase> filterPhases(
    Iterable<VocabPhase> phases,
    String level,
  ) {
    return phases
        .where((phase) => phase.phase <= maxBundledPhase(level))
        .map(
          (phase) => VocabPhase(
            phase: phase.phase,
            title: phase.title,
            themes: phase.themes
                .map(
                  (theme) => VocabTheme(
                    id: theme.id,
                    title: theme.title,
                    entries: theme.entries
                        .where(
                          (entry) => allowsBundledEntry(
                            entry,
                            level: level,
                            phase: phase.phase,
                          ),
                        )
                        .toList(growable: false),
                  ),
                )
                .where((theme) => theme.entries.isNotEmpty)
                .toList(growable: false),
          ),
        )
        .where((phase) => phase.themes.isNotEmpty)
        .toList(growable: false);
  }

  static Iterable<VocabEntry> entriesForLevel(
    Iterable<VocabPhase> phases,
    String level,
  ) sync* {
    for (final phase in filterPhases(phases, level)) {
      for (final theme in phase.themes) {
        yield* theme.entries;
      }
    }
  }

  static bool allowsBundledEntry(
    VocabEntry entry, {
    required String level,
    required int phase,
  }) {
    if (phase > maxBundledPhase(level)) return false;
    if (rank(level) == 1) return _isBeginnerCard(entry);
    return true;
  }

  static bool allowsGeneratedEntry(VocabEntry entry, String level) {
    final band = rank(level);
    final french = entry.fr.trim();
    final english = entry.en.trim();
    if (french.isEmpty || english.isEmpty) return false;
    if (band == 1) return _isBeginnerCard(entry);
    if (band == 2) {
      return _wordCount(french) <= 4 &&
          !_containsAlternativeForms(french) &&
          french.length <= 32;
    }
    return _wordCount(french) <= (band == 3 ? 6 : 10);
  }

  static List<VocabEntry> filterGenerated(
    Iterable<VocabEntry> entries,
    String level,
  ) {
    final result = <VocabEntry>[];
    final seen = <String>{};
    for (final entry in entries) {
      final key = entry.fr.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      if (allowsGeneratedEntry(entry, level)) result.add(entry);
    }
    return result;
  }

  static bool isSetAtOrBelow(String setLevel, String learnerLevel) =>
      rank(setLevel) <= rank(learnerLevel);

  static String calibration(String rawLevel) {
    return switch (normalise(rawLevel)) {
      'A1' =>
        '''
VOCABULARY CALIBRATION A1: use only very common beginner French. Prefer one
short word, or an extremely common two-word chunk such as "s'il vous plaît".
Avoid professional, academic, abstract, literary, idiomatic, formal-letter,
immigration, legal, medical, or exam vocabulary. Avoid rare synonyms. If a
word might be unfamiliar to a first-week learner, replace it with a simpler
word.''',
      'A2' =>
        '''
VOCABULARY CALIBRATION A2: use common everyday French for routines, shopping,
transport, work, housing, health, and simple social situations. Avoid rare,
literary, abstract, formal, or exam-specific vocabulary unless the scenario
requires it and the word is explicitly taught.''',
      'B1' =>
        '''
VOCABULARY CALIBRATION B1: use practical everyday and moderately varied French.
Introduce abstract or professional words only when the learner's goal requires
them, and explain them in simple English.''',
      _ =>
        '''
VOCABULARY CALIBRATION B2: use precise natural French appropriate to the
learner's selected professional, academic, or exam context. Avoid needless
rarity; relevance still matters more than difficulty.''',
    };
  }

  static bool _isBeginnerCard(VocabEntry entry) {
    final french = entry.fr.trim();
    final english = entry.en.trim();
    return _wordCount(french) <= 2 &&
        french.length <= 18 &&
        english.length <= 34 &&
        !_containsAlternativeForms(french) &&
        !french.contains(RegExp(r'[!?;:]'));
  }

  static bool _containsAlternativeForms(String value) =>
      value.contains('/') || value.contains('(') || value.contains(')');

  static int _wordCount(String value) =>
      value.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).length;
}
