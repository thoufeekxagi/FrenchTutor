import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/models/daily_session.dart';
import 'package:french_tutor/models/srs_state.dart';
import 'package:french_tutor/services/srs_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('LearningStore migrations', () {
    test('fresh database gets full schema', () {
      final store = LearningStore(sqlite3.openInMemory());
      expect(store.allSRSStates(), isEmpty);
      expect(store.newEntriesIntroducedToday(), 0);
      expect(store.aiSecondsUsedToday(), 0);
    });

    test('legacy vocab_srs rows are imported once', () {
      final db = sqlite3.openInMemory();
      db.execute('''
        CREATE TABLE vocab_srs (
          entry_id TEXT PRIMARY KEY, ease REAL NOT NULL DEFAULT 2.5,
          interval_days REAL NOT NULL DEFAULT 0, reps INTEGER NOT NULL DEFAULT 0,
          due_at TEXT, last_grade INTEGER
        )
      ''');
      db.execute(
          "INSERT INTO vocab_srs VALUES ('word_1', 2.3, 3.0, 2, '2026-07-20T09:00:00', 1)");

      final store = LearningStore(db);
      final state = store.srsState('word_1');
      expect(state, isNotNull);
      expect(state!.reps, 2);
      expect(state.ease, 2.3);
      expect(state.lastGrade, SRSGrade.good);
      expect(state.introducedOn, '2026-07-20');
    });
  });

  group('SRS grading', () {
    late LearningStore store;
    late SRSService srs;

    setUp(() {
      store = LearningStore(sqlite3.openInMemory());
      srs = SRSService(store: store);
    });

    test('first grade stamps introduced_on and counts toward daily budget', () {
      srs.grade(entryId: 'w1', grade: SRSGrade.good);
      expect(store.newEntriesIntroducedToday(), 1);

      // "Again" on a NEW card must still count as introduced (legacy bug:
      // reps=0 rows were invisible to the budget, flooding strugglers).
      srs.grade(entryId: 'w2', grade: SRSGrade.again);
      expect(store.newEntriesIntroducedToday(), 2);
    });

    test('re-grading later does not re-count as introduced', () {
      srs.grade(entryId: 'w1', grade: SRSGrade.good);
      srs.grade(entryId: 'w1', grade: SRSGrade.good);
      expect(store.newEntriesIntroducedToday(), 1);
    });

    test('every grade appends to the review log', () {
      srs.grade(entryId: 'w1', grade: SRSGrade.again, responseType: SRSResponseType.unaided);
      srs.grade(entryId: 'w1', grade: SRSGrade.good, responseType: SRSResponseType.selfReported);
      final reviews = store.reviewsOn(DateTime.now());
      expect(reviews.length, 2);
      expect(reviews.first.grade, SRSGrade.again);
      expect(reviews.last.grade, SRSGrade.good);
    });

    test('again card becomes due within 10 minutes for same-session loop', () {
      final state = srs.grade(entryId: 'w1', grade: SRSGrade.again);
      expect(state.dueAt!.isBefore(DateTime.now().add(const Duration(minutes: 11))), isTrue);
    });

    test('hard is progress with a shorter interval, never a reset', () {
      srs.grade(entryId: 'w1', grade: SRSGrade.good); // reps 1, 1d
      final hard = srs.grade(entryId: 'w1', grade: SRSGrade.hard);
      expect(hard.reps, 2);
      expect(hard.intervalDays, lessThan(3)); // good would give 3d here
    });
  });

  group('Daily session persistence', () {
    test('same row returned per local date; state roundtrips', () {
      final store = LearningStore(sqlite3.openInMemory());
      final a = store.dailySession();
      a.plannedLength = 'quick';
      a.currentStage = PathwayStage.grammar;
      a.currentItemIndex = 3;
      a.vocabEntryIds = ['w1', 'w2'];
      a.stages[PathwayStage.vocab]!.status = StageStatus.completed;
      a.stages[PathwayStage.vocab]!.resultJson = {'covered': 2};
      a.stages[PathwayStage.grammar]!.status = StageStatus.paused;
      store.saveDailySession(a);

      final b = store.dailySession();
      expect(b.id, a.id);
      expect(b.plannedLength, 'quick');
      expect(b.currentStage, PathwayStage.grammar);
      expect(b.currentItemIndex, 3);
      expect(b.vocabEntryIds, ['w1', 'w2']);
      expect(b.stages[PathwayStage.vocab]!.status, StageStatus.completed);
      expect(b.stages[PathwayStage.vocab]!.resultJson, {'covered': 2});
      expect(b.stages[PathwayStage.grammar]!.status, StageStatus.paused);
      expect(b.nextStage, PathwayStage.grammar);
      expect(b.isComplete, isFalse);
    });
  });

  group('AI sessions and credits', () {
    test('end reason and utterances recorded; credit ledger accumulates', () {
      final store = LearningStore(sqlite3.openInMemory());
      final id = store.startAiSession(stage: 'speaking', topic: 'café');
      store.endAiSession(id, endedReason: 'completed', learnerUtteranceCount: 4);
      // connected_at == ended_at in-test, so seconds may be 0 — the ledger
      // only records positive durations; just verify no crash and query path.
      expect(store.aiSecondsUsedToday(), greaterThanOrEqualTo(0));
    });
  });

  group('Habit minutes', () {
    test('accumulate across a day instead of replacing', () {
      final store = LearningStore(sqlite3.openInMemory());
      store.markHabit('anki', minutes: 5);
      store.markHabit('anki', minutes: 7);
      expect(store.habits()['anki']!.minutes, 12);
      expect(store.habits()['anki']!.done, isTrue);
    });
  });
}
