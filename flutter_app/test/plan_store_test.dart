import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/plan_store.dart';
import 'package:french_tutor/orchestration/models/learning_plan.dart';
import 'package:french_tutor/orchestration/models/plan_reason.dart';
import 'package:french_tutor/orchestration/models/plan_task.dart';
import 'package:sqlite3/sqlite3.dart';

PlanTaskRecord _task({
  required String id,
  required String planId,
  int sequence = 0,
  PlanTaskStatus status = PlanTaskStatus.pending,
}) => PlanTaskRecord(
  id: id,
  planId: planId,
  sequence: sequence,
  contentItemId: 'content-$id',
  requirement: PlanTaskRequirement.must,
  estimatedMinutes: 10,
  reasonCode: PlanReasonCode.dueReview,
  targetCompetencyIds: const ['competency-1'],
  status: status,
);

PlanSnapshot _plan({
  required String id,
  String localDate = '2026-03-01',
  List<PlanTaskRecord>? tasks,
  String? replacesPlanId,
}) => PlanSnapshot(
  id: id,
  localDate: localDate,
  availableMinutes: 30,
  primaryPriority: 'due_review',
  explanation: 'Test plan.',
  plannerVersion: 'test-v1',
  status: PlanSnapshotStatus.generated,
  replacesPlanId: replacesPlanId,
  tasks: tasks ??
      [
        _task(id: '$id-task-1', planId: id),
        _task(id: '$id-task-2', planId: id, sequence: 1),
      ],
);

void main() {
  late Database db;
  late PlanStore store;

  setUp(() {
    db = sqlite3.openInMemory();
    store = PlanStore(db);
  });

  tearDown(() => db.dispose());

  test('round-trips a plan and its ordered tasks', () {
    store.savePlan(_plan(id: 'plan-1'));

    final loaded = store.activePlanForDate('2026-03-01');
    expect(loaded, isNotNull);
    expect(loaded!.tasks.map((t) => t.id), ['plan-1-task-1', 'plan-1-task-2']);
    expect(loaded.status, PlanSnapshotStatus.generated);
  });

  test('starting a task locks the plan into inProgress', () {
    store.savePlan(_plan(id: 'plan-1'));

    store.startTask('plan-1-task-1');

    final loaded = store.byId('plan-1')!;
    expect(loaded.status, PlanSnapshotStatus.inProgress);
    expect(loaded.tasks.first.status, PlanTaskStatus.active);
    expect(loaded.startedAt, isNotNull);
  });

  test('completing every task marks the plan completed', () {
    store.savePlan(_plan(id: 'plan-1'));
    store.startTask('plan-1-task-1');

    store.completeTask(taskId: 'plan-1-task-1', status: PlanTaskStatus.completed);
    expect(store.byId('plan-1')!.status, PlanSnapshotStatus.inProgress);

    store.completeTask(taskId: 'plan-1-task-2', status: PlanTaskStatus.skipped);
    final loaded = store.byId('plan-1')!;
    expect(loaded.status, PlanSnapshotStatus.completed);
    expect(loaded.completedAt, isNotNull);
  });

  test('rejects mutation of a plan that has been replaced', () {
    final original = _plan(id: 'plan-1');
    store.savePlan(original);
    final replacement = _plan(id: 'plan-2', replacesPlanId: 'plan-1');
    store.replan(replaces: original, newPlan: replacement);

    expect(
      () => store.startTask('plan-1-task-1'),
      throwsA(isA<PlanImmutableException>()),
    );
  });

  test('replan retires the prior plan so only the new one is active', () {
    final original = _plan(id: 'plan-1');
    store.savePlan(original);
    final replacement = _plan(id: 'plan-2', replacesPlanId: 'plan-1');

    store.replan(replaces: original, newPlan: replacement);

    final active = store.activePlanForDate('2026-03-01')!;
    expect(active.id, 'plan-2');
    expect(store.byId('plan-1')!.status, PlanSnapshotStatus.replaced);
  });
}
