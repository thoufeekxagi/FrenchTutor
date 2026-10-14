import '../../models/content_models.dart';
import '../../models/srs_state.dart';
import '../lesson/v3_lesson.dart';

/// Daily review for the course, built only from words the learner has really
/// met in their lessons. It grows as they learn: finishing a lesson (or getting
/// part way through one) adds that lesson's words, and nothing else appears.
///
/// Pure, so every rule can be tested without a phone or a database.
abstract final class V3ReviewQueue {
  /// The word steps the learner has seen, in the order they met them.
  ///
  /// - A finished lesson contributes all of its words.
  /// - An unfinished lesson contributes the words up to the furthest step they
  ///   reached ([frontier], the real-progress rule), and nothing beyond it.
  /// - A word taught twice is listed once.
  static List<VocabEntry> learnedWords(
    List<V3Lesson> course,
    Set<String> done,
    Map<String, int> frontier,
  ) {
    final seen = <String>{};
    final out = <VocabEntry>[];
    for (final lesson in course) {
      if (lesson.dev) continue;
      final reached = done.contains(lesson.id)
          ? lesson.steps.length - 1
          : (frontier[lesson.id] ?? -1);
      for (var i = 0; i < lesson.steps.length && i <= reached; i++) {
        final step = lesson.steps[i];
        if (step is! V3WordStep) continue;
        final key = step.fr.trim().toLowerCase();
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(
          VocabEntry(
            id: idFor(step.fr),
            en: step.en,
            fr: step.fr,
            phonetic: step.sound,
          ),
        );
      }
    }
    return out;
  }

  /// A stable id, so a word keeps its review history across lessons and
  /// reinstalls.
  static String idFor(String fr) => 'v3:${fr.trim().toLowerCase()}';

  /// Today's cards: what is due first (longest overdue first), then new words
  /// in the order they were taught, within [newBudget] new cards a day and
  /// [targetSize] cards in all.
  static List<VocabEntry> build({
    required List<VocabEntry> learned,
    required Map<String, SRSState> states,
    required DateTime now,
    required int targetSize,
    required int newBudget,
  }) {
    final due = <VocabEntry>[];
    final unseen = <VocabEntry>[];
    for (final entry in learned) {
      final state = states[entry.id];
      if (state == null) {
        unseen.add(entry);
      } else if (state.dueAt != null && state.dueAt!.isBefore(now)) {
        due.add(entry);
      }
    }
    due.sort((a, b) => states[a.id]!.dueAt!.compareTo(states[b.id]!.dueAt!));
    final dueCount = due.length < targetSize ? due.length : targetSize;
    final newCount = (targetSize - dueCount).clamp(0, newBudget);
    return [...due.take(dueCount), ...unseen.take(newCount)];
  }
}
