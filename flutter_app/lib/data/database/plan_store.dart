import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../orchestration/models/competency.dart';
import '../../orchestration/models/learning_plan.dart';
import '../../orchestration/models/plan_reason.dart';
import '../../orchestration/models/plan_task.dart';
import '../../services/sync_service.dart';
import 'app_migrations.dart';

class PlanImmutableException implements Exception {
  const PlanImmutableException(this.planId);

  final String planId;

  @override
  String toString() =>
      'PlanImmutableException: plan $planId has been replaced and can no '
      'longer be modified';
}

/// Persists immutable [PlanSnapshot]s (plan sections 5.6/5.7/8.7). A plan is
/// written once by [savePlan]. From then on only task progress
/// (`status`/`startedAt`/`completedAt`/`resultSummary`) may change; the
/// plan's own task list, reasons, and estimates are never rewritten. Explicit
/// replanning goes through [replan], which marks the prior plan `replaced`
/// and inserts a new one linked to it — it never edits history.
class PlanStore {
  PlanStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  String _now() => DateTime.now().toUtc().toIso8601String();

  void savePlan(PlanSnapshot plan) {
    _db.execute('BEGIN');
    try {
      _insertPlanRow(plan);
      for (final task in plan.tasks) {
        _insertTaskRow(task);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    unawaited(_sync?.syncPlan(plan));
  }

  /// Marks [replaces] `replaced` and persists [newPlan] linked to it via
  /// `replacesPlanId`. Both happen in one transaction so a crash mid-replan
  /// can never leave two simultaneously-active plans for the same date.
  void replan({required PlanSnapshot replaces, required PlanSnapshot newPlan}) {
    if (newPlan.replacesPlanId != replaces.id) {
      throw ArgumentError.value(
        newPlan.replacesPlanId,
        'newPlan.replacesPlanId',
        'must equal replaces.id',
      );
    }
    _db.execute('BEGIN');
    try {
      _db.execute(
        "UPDATE learning_plans SET status = 'replaced', updated_at = ? WHERE id = ?",
        [_now(), replaces.id],
      );
      _insertPlanRow(newPlan);
      for (final task in newPlan.tasks) {
        _insertTaskRow(task);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    unawaited(_sync?.markPlanReplaced(replaces.id));
    unawaited(_sync?.syncPlan(newPlan));
  }

  /// The plan currently governing [localDate] — the latest non-replaced row,
  /// which is unique by construction since [replan] atomically retires the
  /// one it supersedes.
  PlanSnapshot? activePlanForDate(String localDate, {String? userId}) {
    final rows = _db.select(
      "SELECT * FROM learning_plans WHERE user_id IS ? AND local_date = ? "
      "AND status != 'replaced' AND deleted_at IS NULL "
      "ORDER BY created_at DESC LIMIT 1",
      [userId, localDate],
    );
    if (rows.isEmpty) return null;
    return _planFromRow(rows.first);
  }

  /// The mission id from the most recently generated plan (any date, any
  /// status), so a new day's plan can avoid immediately repeating it.
  String? mostRecentMissionId({String? userId}) {
    final rows = _db.select(
      "SELECT input_snapshot_json FROM learning_plans WHERE user_id IS ? "
      "AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1",
      [userId],
    );
    if (rows.isEmpty) return null;
    final snapshot =
        (jsonDecode(rows.first['input_snapshot_json'] as String) as Map)
            .cast<String, Object?>();
    return snapshot['missionId'] as String?;
  }

  /// Mission ids from the [limit] most recently generated plans (any date,
  /// any status), so a new plan can avoid repeating anything from recent
  /// history instead of only the single most recent mission — a 1-mission
  /// lookback was trivially defeated by a small scenario pool.
  List<String> recentMissionIds({String? userId, int limit = 40}) {
    final rows = _db.select(
      "SELECT input_snapshot_json FROM learning_plans WHERE user_id IS ? "
      "AND deleted_at IS NULL ORDER BY created_at DESC LIMIT ?",
      [userId, limit],
    );
    final ids = <String>[];
    for (final row in rows) {
      final snapshot =
          (jsonDecode(row['input_snapshot_json'] as String) as Map)
              .cast<String, Object?>();
      final missionId = snapshot['missionId'] as String?;
      if (missionId != null) ids.add(missionId);
    }
    return ids;
  }

  /// Count of missions (plans) completed on [localDate] — the same-day
  /// signal used to escalate difficulty when a learner is practicing a lot
  /// in one day (see `_advanceToNextMission` in today_mission_widget.dart).
  int completedMissionCountForDate(String localDate, {String? userId}) {
    final rows = _db.select(
      "SELECT COUNT(*) AS c FROM learning_plans WHERE user_id IS ? "
      "AND local_date = ? AND status = 'completed' AND deleted_at IS NULL",
      [userId, localDate],
    );
    return rows.first['c'] as int;
  }

  /// Lifetime count of plans ever generated (any date, any status) — used
  /// by [RotationPlanner] as a simple, stateless index into the fixed
  /// modality rotation (`count % rotationLength`). No separate counter
  /// table needed; this is just a count of what's already persisted.
  int totalPlanCount({String? userId}) {
    final rows = _db.select(
      "SELECT COUNT(*) AS c FROM learning_plans WHERE user_id IS ? AND deleted_at IS NULL",
      [userId],
    );
    return rows.first['c'] as int;
  }

  PlanSnapshot? byId(String id) {
    final rows = _db.select(
      'SELECT * FROM learning_plans WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    if (rows.isEmpty) return null;
    return _planFromRow(rows.first);
  }

  void startTask(String taskId, {DateTime? at}) {
    final plan = _planForTask(taskId);
    _guardMutable(plan);
    final timestamp = (at ?? DateTime.now()).toUtc().toIso8601String();
    _db.execute(
      "UPDATE plan_tasks SET status = 'active', started_at = COALESCE(started_at, ?), updated_at = ? WHERE id = ?",
      [timestamp, _now(), taskId],
    );
    _db.execute(
      "UPDATE learning_plans SET status = 'inProgress', started_at = COALESCE(started_at, ?), updated_at = ? "
      "WHERE id = ? AND status = 'generated'",
      [timestamp, _now(), plan.id],
    );
    unawaited(
      _sync?.syncPlanTask(
        taskId: taskId,
        status: 'active',
        startedAt: DateTime.parse(timestamp),
      ),
    );
  }

  void completeTask({
    required String taskId,
    required PlanTaskStatus status,
    Map<String, Object?>? resultSummary,
    DateTime? at,
  }) {
    if (status != PlanTaskStatus.completed &&
        status != PlanTaskStatus.skipped) {
      throw ArgumentError.value(
        status,
        'status',
        'must be completed or skipped',
      );
    }
    final plan = _planForTask(taskId);
    _guardMutable(plan);
    final timestamp = (at ?? DateTime.now()).toUtc().toIso8601String();
    _db.execute(
      'UPDATE plan_tasks SET status = ?, completed_at = ?, result_summary_json = ?, updated_at = ? WHERE id = ?',
      [
        status.name,
        timestamp,
        resultSummary == null ? null : jsonEncode(resultSummary),
        _now(),
        taskId,
      ],
    );
    unawaited(
      _sync?.syncPlanTask(
        taskId: taskId,
        status: status.name,
        completedAt: DateTime.parse(timestamp),
        resultSummary: resultSummary,
      ),
    );

    final remaining = _db.select(
      "SELECT COUNT(*) AS c FROM plan_tasks WHERE plan_id = ? AND status NOT IN ('completed', 'skipped')",
      [plan.id],
    );
    if ((remaining.first['c'] as int) == 0) {
      _db.execute(
        "UPDATE learning_plans SET status = 'completed', completed_at = ?, updated_at = ? WHERE id = ?",
        [timestamp, _now(), plan.id],
      );
      unawaited(
        _sync?.updatePlanStatus(
          planId: plan.id,
          status: 'completed',
          completedAt: DateTime.parse(timestamp),
        ),
      );
    }
  }

  PlanSnapshot _planForTask(String taskId) {
    final rows = _db.select('SELECT plan_id FROM plan_tasks WHERE id = ?', [
      taskId,
    ]);
    if (rows.isEmpty) {
      throw ArgumentError.value(taskId, 'taskId', 'not found');
    }
    final plan = byId(rows.first['plan_id'] as String);
    if (plan == null) {
      throw StateError('plan_tasks references a missing plan: $taskId');
    }
    return plan;
  }

  void _guardMutable(PlanSnapshot plan) {
    if (plan.status == PlanSnapshotStatus.replaced) {
      throw PlanImmutableException(plan.id);
    }
  }

  void _insertPlanRow(PlanSnapshot plan) {
    final now = _now();
    _db.execute(
      '''INSERT INTO learning_plans
         (id, user_id, local_date, available_minutes, environment_json,
          primary_priority, explanation, planner_version, input_snapshot_json,
          status, replaces_plan_id, replan_reason, started_at, completed_at,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        plan.id,
        plan.userId,
        plan.localDate,
        plan.availableMinutes,
        jsonEncode(plan.environment),
        plan.primaryPriority,
        plan.explanation,
        plan.plannerVersion,
        jsonEncode(plan.inputSnapshot),
        plan.status.name,
        plan.replacesPlanId,
        plan.replanReason,
        plan.startedAt?.toUtc().toIso8601String(),
        plan.completedAt?.toUtc().toIso8601String(),
        now,
        now,
      ],
    );
  }

  void _insertTaskRow(PlanTaskRecord task) {
    final now = _now();
    _db.execute(
      '''INSERT INTO plan_tasks
         (id, user_id, plan_id, sequence, content_item_id, modality,
          requirement, estimated_minutes, reason_code, reason_detail_json,
          target_competency_ids_json, status, started_at, completed_at,
          result_summary_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        task.id,
        task.userId,
        task.planId,
        task.sequence,
        task.contentItemId,
        task.modality.wireName,
        task.requirement.name,
        task.estimatedMinutes,
        task.reasonCode.wireName,
        jsonEncode(task.reasonDetail),
        jsonEncode(task.targetCompetencyIds),
        task.status.name,
        task.startedAt?.toUtc().toIso8601String(),
        task.completedAt?.toUtc().toIso8601String(),
        task.resultSummary == null ? null : jsonEncode(task.resultSummary),
        now,
        now,
      ],
    );
  }

  PlanSnapshot _planFromRow(Row row) {
    final taskRows = _db.select(
      'SELECT * FROM plan_tasks WHERE plan_id = ? AND deleted_at IS NULL ORDER BY sequence',
      [row['id'] as String],
    );
    return PlanSnapshot(
      id: row['id'] as String,
      userId: row['user_id'] as String?,
      localDate: row['local_date'] as String,
      availableMinutes: row['available_minutes'] as int,
      environment: (jsonDecode(row['environment_json'] as String) as Map)
          .cast<String, Object?>(),
      primaryPriority: row['primary_priority'] as String,
      explanation: row['explanation'] as String,
      plannerVersion: row['planner_version'] as String,
      inputSnapshot: (jsonDecode(row['input_snapshot_json'] as String) as Map)
          .cast<String, Object?>(),
      status: PlanSnapshotStatus.fromWireName(row['status'] as String),
      replacesPlanId: row['replaces_plan_id'] as String?,
      replanReason: row['replan_reason'] as String?,
      startedAt: _parseDate(row['started_at']),
      completedAt: _parseDate(row['completed_at']),
      tasks: taskRows.map(_taskFromRow).toList(growable: false),
    );
  }

  PlanTaskRecord _taskFromRow(Row row) => PlanTaskRecord(
    id: row['id'] as String,
    userId: row['user_id'] as String?,
    planId: row['plan_id'] as String,
    sequence: row['sequence'] as int,
    contentItemId: row['content_item_id'] as String,
    modality: PerformanceModality.fromWireName(row['modality'] as String),
    requirement: PlanTaskRequirement.fromWireName(row['requirement'] as String),
    estimatedMinutes: row['estimated_minutes'] as int,
    reasonCode: PlanReasonCode.fromWireName(row['reason_code'] as String),
    reasonDetail: (jsonDecode(row['reason_detail_json'] as String) as Map)
        .cast<String, Object?>(),
    targetCompetencyIds: List<String>.from(
      jsonDecode(row['target_competency_ids_json'] as String) as List,
    ),
    status: PlanTaskStatus.fromWireName(row['status'] as String),
    startedAt: _parseDate(row['started_at']),
    completedAt: _parseDate(row['completed_at']),
    resultSummary: row['result_summary_json'] == null
        ? null
        : (jsonDecode(row['result_summary_json'] as String) as Map)
              .cast<String, Object?>(),
  );
}

DateTime? _parseDate(Object? raw) =>
    raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
