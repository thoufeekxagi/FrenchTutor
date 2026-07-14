import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/flow/stage_outcome.dart';
import 'package:french_tutor/models/daily_session.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Daily Path completion semantics', () {
    late LearningStore store;

    setUp(() => store = LearningStore(sqlite3.openInMemory()));

    test('paused stage stays the next stage after a restart', () {
      final session = store.dailySession();
      session.stages[PathwayStage.vocab]!.status = StageStatus.completed;
      session.stages[PathwayStage.grammar]!.status = StageStatus.paused;
      store.saveDailySession(session);

      // Simulate relaunch: fresh read from disk.
      final resumed = store.dailySession();
      expect(resumed.nextStage, PathwayStage.grammar);
      expect(resumed.stages[PathwayStage.grammar]!.status, StageStatus.paused);
      expect(resumed.isComplete, isFalse);
    });

    test('skipped stages count toward day completion, paused do not', () {
      final session = store.dailySession();
      for (final s in PathwayStage.values) {
        session.stages[s]!.status = StageStatus.completed;
      }
      session.stages[PathwayStage.writing]!.status = StageStatus.skipped;
      store.saveDailySession(session);
      expect(store.dailySession().isComplete, isTrue);

      session.stages[PathwayStage.speaking]!.status = StageStatus.paused;
      store.saveDailySession(session);
      expect(store.dailySession().isComplete, isFalse);
      expect(store.dailySession().nextStage, PathwayStage.speaking);
    });

    test('fixed daily content survives a restart', () {
      final session = store.dailySession();
      session.vocabEntryIds = ['a', 'b', 'c'];
      session.readingPassageJson = {
        'id': 'p1',
        'title': 'Au café',
        'segments': [],
        'fullText': 'Bonjour.',
      };
      store.saveDailySession(session);

      final resumed = store.dailySession();
      expect(resumed.vocabEntryIds, ['a', 'b', 'c']);
      expect(resumed.readingPassageJson!['title'], 'Au café');
    });
  });

  group('Speaking completion threshold', () {
    test('silent, short, or unconnected calls never meet it', () {
      const cancelled = SpeakingResult(
          connected: false, durationSeconds: 0, learnerUtteranceCount: 0, endedReason: 'cancelled');
      const silent = SpeakingResult(
          connected: true, durationSeconds: 120, learnerUtteranceCount: 0, endedReason: 'completed');
      const tooShort = SpeakingResult(
          connected: true, durationSeconds: 10, learnerUtteranceCount: 2, endedReason: 'completed');
      const real = SpeakingResult(
          connected: true, durationSeconds: 95, learnerUtteranceCount: 6, endedReason: 'completed');

      expect(cancelled.meetsThreshold, isFalse);
      expect(silent.meetsThreshold, isFalse);
      expect(tooShort.meetsThreshold, isFalse);
      expect(real.meetsThreshold, isTrue);
    });
  });

  group('StageOutcome', () {
    test('paused carries partial evidence without completing', () {
      const outcome = StageOutcome<int>.paused(result: 3, reason: 'disconnected');
      expect(outcome.isCompleted, isFalse);
      expect(outcome.result, 3);
      expect(outcome.reason, 'disconnected');
    });
  });
}
