import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/competency_state_store.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/competency_state.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late CompetencyStateStore store;

  setUp(() {
    db = sqlite3.openInMemory();
    store = CompetencyStateStore(db);
  });

  tearDown(() => db.dispose());

  CompetencyState state({
    String competencyId = 'competency-1',
    PerformanceModality modality = PerformanceModality.readingRecognition,
    int evidenceCount = 5,
    DateTime? nextReviewAt,
  }) => CompetencyState(
    competencyId: competencyId,
    modality: modality,
    masteryEstimate: 0.7,
    confidence: 0.6,
    retentionStrength: 0.42,
    evidenceCount: evidenceCount,
    transferStatus: TransferStatus.singleModality,
    learnerModelType: 'contextual_bkt',
    modelVersion: 'test-v1',
    nextReviewAt: nextReviewAt,
    lastObservedAt: DateTime.utc(2026, 3, 1),
  );

  test('round-trips a cache row including its evidence count', () {
    store.replaceAll(null, [state()]);

    final all = store.all();
    expect(all, hasLength(1));
    expect(all.single.evidenceCount, 5);
    expect(all.single.transferStatus, TransferStatus.singleModality);

    final byCompetency = store.byCompetency(
      competencyId: 'competency-1',
      modality: PerformanceModality.readingRecognition,
    );
    expect(byCompetency, isNotNull);
    expect(byCompetency!.masteryEstimate, 0.7);
  });

  test('replaceAll discards stale rows instead of accumulating them', () {
    store.replaceAll(null, [state(competencyId: 'a'), state(competencyId: 'b')]);
    store.replaceAll(null, [state(competencyId: 'a')]);

    expect(store.all().map((s) => s.competencyId), ['a']);
  });

  test('dueForReview only returns rows whose schedule has passed', () {
    final now = DateTime.utc(2026, 6, 1);
    store.replaceAll(null, [
      state(competencyId: 'overdue', nextReviewAt: now.subtract(const Duration(days: 1))),
      state(competencyId: 'future', nextReviewAt: now.add(const Duration(days: 1))),
      state(competencyId: 'none', nextReviewAt: null),
    ]);

    final due = store.dueForReview(now: now);
    expect(due.map((s) => s.competencyId), ['overdue']);
  });

  test('keeps separate caches per user', () {
    store.replaceAll('user-a', [state(competencyId: 'a')]);
    store.replaceAll('user-b', [state(competencyId: 'b')]);

    expect(store.all(userId: 'user-a').map((s) => s.competencyId), ['a']);
    expect(store.all(userId: 'user-b').map((s) => s.competencyId), ['b']);
  });
}
