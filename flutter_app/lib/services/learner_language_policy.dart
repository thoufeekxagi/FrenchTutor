/// Learner-facing language rules shared by every generated practice.
///
/// French is the target language, but it must not become the instruction
/// language for a beginner. Keeping this contract in one place prevents each
/// practice generator from slowly inventing a different interpretation of
/// A1/A2 support.
abstract final class LearnerLanguagePolicy {
  static String normalize(String rawLevel) {
    final value = rawLevel.trim().toUpperCase();
    return switch (value) {
      'A1' || 'ZERO' || 'BASICS' || 'UNSURE' => 'A1',
      'A2' => 'A2',
      'B1' || 'CONVERSATIONAL' => 'B1',
      'B2' => 'B2',
      'C1' => 'C1',
      'C2' => 'C2',
      _ => 'A1',
    };
  }

  static bool isEnglishFirst(String rawLevel) {
    final band = normalize(rawLevel);
    return band == 'A1' || band == 'A2';
  }

  /// Prompt block for content that reaches the learner's eyes or ears.
  ///
  /// The French fields remain intentional target material. English fields are
  /// the support layer and must explain the exact French beside them, never a
  /// different or more advanced sentence.
  static String promptBlock(String rawLevel) {
    final band = normalize(rawLevel);
    if (isEnglishFirst(band)) {
      return '''
LEARNER-FACING LANGUAGE POLICY for $band, FOLLOW EXACTLY:
- English is the primary support language for the learner-facing setup.
- Write titles, subtitles, summaries, headings, instructions, prompts,
  directions, labels, grammar notes, tips, goals, feedback, and metadata in
  plain, natural English.
- French is the language being taught. Keep French in target sentences,
  dialogue, word choices, answer choices, and examples only where the lesson
  requires the learner to see or produce French.
- Every French sentence, line, option, or target must have an accurate English
  meaning in its paired English field. Never leave a beginner-facing French
  explanation or French-only instruction without English support.
- Put the English support before or alongside the French in the UI contract.
  Do not make an A1/A2 learner decode a French title or instruction before
  they can understand what to do.
- Keep English concise and concrete. Do not translate the answer in a way that
  gives away a multiple-choice solution.
''';
    }
    if (band == 'B1' || band == 'B2') {
      return '''
LEARNER-FACING LANGUAGE POLICY for $band:
- French may lead the lesson setup and explanations when natural, but keep
  English support fields accurate for titles, summaries, instructions, and
  teaching notes so the learner can verify meaning.
- French target material remains authoritative. Keep every paired translation
  aligned to the exact sentence or option it explains.
- Increase French naturally with the level; do not use advanced French merely
  to make a lesson sound sophisticated.
''';
    }
    return '''
LEARNER-FACING LANGUAGE POLICY for $band:
- French is the primary teaching language. Use English only as concise,
  accurate support where the output contract provides it.
- Keep every translation and teaching note tied to the exact French material.
''';
  }

  /// A safe display order for a French/English pair in compact UI surfaces.
  static String displayPair({
    required String french,
    required String english,
    required String levelBand,
  }) {
    final fr = french.trim();
    final en = english.trim();
    if (en.isEmpty) return fr;
    if (isEnglishFirst(levelBand)) return '$en\n$fr';
    return '$fr\n$en';
  }
}
