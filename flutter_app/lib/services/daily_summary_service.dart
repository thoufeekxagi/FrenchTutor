import '../data/content_service.dart';
import '../data/database/learning_store.dart';
import '../models/content_models.dart';
import '../models/daily_session.dart';
import '../models/srs_state.dart';

/// Everything the learner earned today, computed ENTIRELY from local data
/// (PILOT_EXECUTION_PLAN.md P1.4) — no LLM call, no network, no cost. This is
/// the "here's what your 15 minutes bought you" screen: the visible-value loop
/// that makes the daily habit worth paying for.
class DailySummary {
  DailySummary({
    required this.stagesCompleted,
    required this.stagesTotal,
    required this.wordsPracticed,
    required this.hardWords,
    required this.pronunciationFocus,
    required this.writingScore,
    required this.speakingSeconds,
    required this.learnerUtterances,
    required this.sceneTitle,
  });

  final int stagesCompleted;
  final int stagesTotal;

  /// Every word the learner touched today (vocab stage credit).
  final List<VocabEntry> wordsPracticed;

  /// Words graded again/hard today — tomorrow's warm-up list, hardest first.
  final List<({VocabEntry entry, int struggles})> hardWords;

  /// Recurring mistake patterns worth one line of attention.
  final List<MistakeTag> pronunciationFocus;

  final double? writingScore;
  final int speakingSeconds;
  final int learnerUtterances;

  /// The scenario the learner acted out today (e.g. "At the bakery").
  final String? sceneTitle;

  /// Whether there is anything worth showing yet.
  bool get hasActivity =>
      stagesCompleted > 0 ||
      wordsPracticed.isNotEmpty ||
      speakingSeconds > 0 ||
      writingScore != null;
}

class DailySummaryService {
  DailySummaryService({required this.store, ContentService? content})
    : content = content ?? ContentService.shared;

  final LearningStore store;
  final ContentService content;

  DailySummary compute({DateTime? on}) {
    final day = on ?? DateTime.now();
    final session = store.dailySession(on: day);

    // Stage progress — skipped counts toward the day (a deliberate choice),
    // but only completions are celebrated.
    var completed = 0;
    for (final record in session.stages.values) {
      if (record.status == StageStatus.completed) completed += 1;
    }

    // Words practiced: the vocab stage's persisted credit.
    final vocabJson = session.stages[PathwayStage.vocab]?.resultJson;
    final wordIdsRaw = vocabJson?['wordIds'];
    final wordIds = wordIdsRaw is List
        ? wordIdsRaw.whereType<String>().toList()
        : const <String>[];
    final wordsPracticed = _entriesByIds(wordIds);

    // Hard words: today's reviews graded again/hard, grouped and ranked.
    // These already carry shortened SRS intervals — this list makes that
    // invisible mechanic VISIBLE ("we'll hit these again tomorrow").
    final struggles = <String, int>{};
    for (final review in store.reviewsOn(day)) {
      if (review.grade == SRSGrade.again || review.grade == SRSGrade.hard) {
        struggles[review.entryId] = (struggles[review.entryId] ?? 0) + 1;
      }
    }
    final hardEntries = _entriesByIds(struggles.keys.toList());
    final hardWords =
        hardEntries
            .map((e) => (entry: e, struggles: struggles[e.id] ?? 1))
            .toList()
          ..sort((a, b) => b.struggles.compareTo(a.struggles));

    // Writing + speaking evidence straight from the persisted stage results.
    // Type-safe reads throughout: a corrupt or legacy-shaped resultJson value
    // degrades to "no data", never to a crash on the dashboard.
    final writingJson = session.stages[PathwayStage.writing]?.resultJson;
    final scoreRaw = writingJson?['score'];
    final writingScore = scoreRaw is num ? scoreRaw.toDouble() : null;
    final speakingJson = session.stages[PathwayStage.speaking]?.resultJson;
    final durationRaw = speakingJson?['durationSeconds'];
    final speakingSeconds = durationRaw is num ? durationRaw.toInt() : 0;
    final utterancesRaw = speakingJson?['utterances'];
    final learnerUtterances = utterancesRaw is num ? utterancesRaw.toInt() : 0;

    String? sceneTitle;
    final passage = session.readingPassageJson;
    if (passage != null && (passage['title'] as String?)?.isNotEmpty == true) {
      sceneTitle = passage['title'] as String;
    }

    return DailySummary(
      stagesCompleted: completed,
      stagesTotal: session.stages.length,
      wordsPracticed: wordsPracticed,
      hardWords: hardWords.take(5).toList(),
      pronunciationFocus: store.topMistakeTags(limit: 3),
      writingScore: writingScore,
      speakingSeconds: speakingSeconds,
      learnerUtterances: learnerUtterances,
      sceneTitle: sceneTitle,
    );
  }

  List<VocabEntry> _entriesByIds(List<String> ids) {
    if (ids.isEmpty) return const [];
    final wanted = ids.toSet();
    return content.vocabPhases
        .expand((p) => p.themes.expand((t) => t.entries))
        .where((e) => wanted.contains(e.id))
        .toList();
  }
}
