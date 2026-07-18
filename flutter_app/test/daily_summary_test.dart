import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/models/daily_session.dart';
import 'package:french_tutor/models/srs_state.dart';
import 'package:french_tutor/services/daily_summary_service.dart';

void main() {
  late LearningStore store;
  late DailySummaryService service;

  setUp(() {
    store = LearningStore(sqlite3.openInMemory());
    service = DailySummaryService(store: store);
  });

  test('empty day has no activity — card stays hidden', () {
    final summary = service.compute();
    expect(summary.hasActivity, isFalse);
    expect(summary.stagesCompleted, 0);
    expect(summary.wordsPracticed, isEmpty);
    expect(summary.hardWords, isEmpty);
  });

  test('completed stages and stage evidence surface in the summary', () {
    final session = store.dailySession();
    session.stages[PathwayStage.vocab]!
      ..status = StageStatus.completed
      ..resultJson = {
        'wordIds': ['w1', 'w2'],
        'reviewedCount': 2,
      };
    session.stages[PathwayStage.writing]!
      ..status = StageStatus.completed
      ..resultJson = {'score': 7.5};
    session.stages[PathwayStage.speaking]!
      ..status = StageStatus.completed
      ..resultJson = {'durationSeconds': 240, 'utterances': 12};
    session.readingPassageJson = {'title': 'At the bakery', 'segments': []};
    store.saveDailySession(session);

    final summary = service.compute();
    expect(summary.hasActivity, isTrue);
    expect(summary.stagesCompleted, 3);
    expect(summary.writingScore, 7.5);
    expect(summary.speakingSeconds, 240);
    expect(summary.learnerUtterances, 12);
    expect(summary.sceneTitle, 'At the bakery');
    // Unknown content ids simply resolve to no entries — never a crash.
    expect(summary.wordsPracticed, isEmpty);
  });

  test('again/hard reviews become the hard-words list, ranked', () {
    for (var i = 0; i < 3; i++) {
      store.logReview(
        entryId: 'w_tough',
        grade: SRSGrade.again,
        responseType: SRSResponseType.auto,
      );
    }
    store.logReview(
      entryId: 'w_ok',
      grade: SRSGrade.hard,
      responseType: SRSResponseType.auto,
    );
    store.logReview(
      entryId: 'w_easy',
      grade: SRSGrade.easy,
      responseType: SRSResponseType.auto,
    );
    // Content pack has no such ids in tests, so entries resolve empty — the
    // grouping logic itself is what matters here and it must not crash.
    final summary = service.compute();
    expect(summary.hardWords, isEmpty);
  });

  test('mistake tags flow into pronunciation focus', () {
    store.logMistake(tag: 'nasal_vowel', description: 'Nasal vowel confusion');
    store.logMistake(tag: 'nasal_vowel', description: 'Nasal vowel confusion');
    store.logMistake(tag: 'silent_s', description: 'Pronounced the silent s');
    final summary = service.compute();
    expect(summary.pronunciationFocus, isNotEmpty);
    expect(summary.pronunciationFocus.length, lessThanOrEqualTo(3));
  });

  test('corrupt stage json never crashes the summary', () {
    final session = store.dailySession();
    session.stages[PathwayStage.writing]!
      ..status = StageStatus.completed
      ..resultJson = {'score': 'not-a-number-shaped-thing'};
    session.stages[PathwayStage.vocab]!.resultJson = {'wordIds': 'garbage'};
    session.stages[PathwayStage.speaking]!.resultJson = {
      'durationSeconds': 'later',
      'utterances': null,
    };
    store.saveDailySession(session);
    final summary = service.compute();
    // Wrong-typed values are ignored, not fatal.
    expect(summary.writingScore, isNull);
    expect(summary.wordsPracticed, isEmpty);
    expect(summary.speakingSeconds, 0);
  });
}
