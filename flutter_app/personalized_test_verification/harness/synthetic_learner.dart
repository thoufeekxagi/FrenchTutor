import 'dart:math';

import 'package:french_tutor/models/srs_state.dart';
import 'gemini_text.dart';

/// Stands in for a real learner's answers so the harness can drive
/// SRSService.grade() and LessonAgentService.gradeWriting() the same way a
/// live session would. Tunable in one place — change the weights to model a
/// stronger/weaker learner and see how pacing responds.
class SyntheticLearner {
  SyntheticLearner({required this.rng});

  final Random rng;

  /// Weighted grade distribution: mostly "good", occasional slip-ups —
  /// tuned so SRS intervals actually grow over 30 days like a real
  /// learner's would, rather than flatlining (all-easy) or thrashing
  /// (all-again).
  static const _gradeWeights = <SRSGrade, double>{
    SRSGrade.good: 0.70,
    SRSGrade.easy: 0.15,
    SRSGrade.hard: 0.10,
    SRSGrade.again: 0.05,
  };

  SRSGrade pickGrade() {
    final roll = rng.nextDouble();
    var cumulative = 0.0;
    for (final entry in _gradeWeights.entries) {
      cumulative += entry.value;
      if (roll <= cumulative) return entry.key;
    }
    return SRSGrade.good;
  }

  /// Asks Gemini to role-play a plausible, imperfect submission for a
  /// writing task at [levelBand] — there's no real learner to type an
  /// answer, so this generates a stand-in with natural minor errors,
  /// separate from (and never a substitute for) the production
  /// `LessonAgentService.gradeWriting` call this harness is actually testing.
  Future<String> writeSubmission({
    required GeminiTextClient client,
    required String levelBand,
    required String promptFr,
    required int minWords,
    required List<String> targetConnectors,
  }) async {
    final prompt =
        'You are role-playing a French learner at CEFR level $levelBand '
        'responding to this writing prompt: "$promptFr"\n\n'
        'Write a plausible answer of at least $minWords words, in French, at '
        'exactly the fluency and error rate a real $levelBand learner would '
        'produce — natural minor grammar/spelling slips are expected and '
        'wanted, not a perfect answer. Try to use at least one of these '
        'connectors if natural: ${targetConnectors.join(", ")}.\n\n'
        'Reply with ONLY the French submission text, nothing else — no '
        'commentary, no markdown, no translation.';
    final raw = await client.generate(prompt);
    return raw.trim();
  }
}
