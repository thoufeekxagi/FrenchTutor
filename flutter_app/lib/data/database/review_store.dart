import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import 'app_migrations.dart';
import '../../services/sync_service.dart';

const _reviewUuid = Uuid();

class ReviewPlanRecord {
  const ReviewPlanRecord({
    required this.id,
    required this.kind,
    required this.requestedMode,
    required this.resolvedMode,
    required this.levelBand,
    required this.goal,
    required this.durationMinutes,
    required this.topic,
    required this.sourceFingerprint,
    required this.brief,
    this.generated = const {},
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String kind;
  final String requestedMode;
  final String resolvedMode;
  final String levelBand;
  final String goal;
  final int durationMinutes;
  final String topic;
  final String sourceFingerprint;
  final Map<String, dynamic> brief;

  /// The generated payload is kept with the plan so a restored plan can be
  /// retried without asking the provider to recreate its lesson.
  final Map<String, dynamic> generated;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ReviewAttemptRecord {
  const ReviewAttemptRecord({
    required this.id,
    required this.planId,
    required this.mode,
    required this.status,
    required this.activityId,
    required this.sessionId,
    required this.score,
    required this.result,
    required this.startedAt,
    required this.completedAt,
  });

  final String id;
  final String planId;
  final String mode;
  final String status;
  final String? activityId;
  final String? sessionId;
  final double? score;
  final Map<String, dynamic>? result;
  final DateTime startedAt;
  final DateTime? completedAt;
}

/// Local-first persistence for the cross-skill Review/Warm-up pipeline.
///
/// The source evidence stays in the normal learning tables. This store only
/// freezes the planner output and tracks generation/attempt state so a review
/// can be retried or resumed without changing its meaning.
class ReviewStore {
  ReviewStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  String _now() => DateTime.now().toUtc().toIso8601String();

  String createPlan({
    required String kind,
    required String requestedMode,
    required String resolvedMode,
    required String levelBand,
    required String goal,
    required int durationMinutes,
    required String topic,
    required String sourceFingerprint,
    required Map<String, dynamic> brief,
    String? userId,
  }) {
    final id = _reviewUuid.v4();
    final now = _now();
    _db.execute(
      '''INSERT INTO review_plans
         (id, user_id, kind, requested_mode, resolved_mode, level_band, goal,
          duration_minutes, topic, source_fingerprint, brief_json, status,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'planned', ?, ?)''',
      [
        id,
        userId,
        kind,
        requestedMode,
        resolvedMode,
        levelBand,
        goal,
        durationMinutes,
        topic,
        sourceFingerprint,
        jsonEncode(brief),
        now,
        now,
      ],
    );
    final targets = brief['targets'];
    if (targets is List) {
      for (final raw in targets) {
        if (raw is! Map) continue;
        final target = raw.cast<String, dynamic>();
        final targetId = _reviewUuid.v4();
        _db.execute(
          '''INSERT INTO review_plan_targets
             (id, plan_id, target_key, target_type, display_text, reason,
              priority, source_ids_json, evidence_json, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            targetId,
            id,
            _text(target['key'], targetId),
            _text(target['type'], 'retrieval'),
            _text(target['text'], ''),
            _text(target['reason'], ''),
            _number(target['priority']),
            jsonEncode(_stringList(target['sourceIds'])),
            jsonEncode(
              target['evidence'] is Map ? target['evidence'] : const {},
            ),
            now,
            now,
          ],
        );
      }
    }
    unawaited(_sync?.syncReviewPlan(id));
    return id;
  }

  void markGenerated(String planId, Map<String, dynamic> generated) {
    final now = _now();
    final currentRows = _db.select(
      'SELECT generated_json FROM review_plans WHERE id = ? AND deleted_at IS NULL',
      [planId],
    );
    final current = currentRows.isEmpty
        ? <String, dynamic>{}
        : _decodeMap(currentRows.first['generated_json']);
    final merged = <String, dynamic>{...current, ...generated};
    _db.execute(
      "UPDATE review_plans SET generated_json = ?, status = 'generated', updated_at = ? WHERE id = ? AND deleted_at IS NULL",
      [jsonEncode(merged), now, planId],
    );
    unawaited(_sync?.syncReviewPlan(planId));
  }

  void updateResolvedMode(String planId, String mode) {
    final normalized = mode.trim().toLowerCase();
    if (normalized.isEmpty) return;
    _db.execute(
      'UPDATE review_plans SET resolved_mode = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [normalized, _now(), planId],
    );
    unawaited(_sync?.syncReviewPlan(planId));
  }

  void markPlanFailed(String planId, Object error) {
    _db.execute(
      "UPDATE review_plans SET status = 'failed', generated_json = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
      [
        jsonEncode({'error': error.toString()}),
        _now(),
        planId,
      ],
    );
    unawaited(_sync?.syncReviewPlan(planId));
  }

  String startAttempt({
    required String planId,
    required String mode,
    String? activityId,
    String? userId,
  }) {
    final id = _reviewUuid.v4();
    final now = _now();
    _db.execute(
      '''INSERT INTO review_attempts
         (id, user_id, plan_id, activity_id, mode, status, started_at,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'started', ?, ?, ?)''',
      [id, userId, planId, activityId, mode, now, now, now],
    );
    _db.execute(
      "UPDATE review_plans SET status = 'started', updated_at = ? WHERE id = ? AND deleted_at IS NULL",
      [now, planId],
    );
    unawaited(_sync?.syncReviewPlan(planId));
    unawaited(_sync?.syncReviewAttempt(id));
    return id;
  }

  void completeAttempt(
    String attemptId, {
    String status = 'completed',
    String? sessionId,
    double? score,
    Map<String, dynamic>? result,
  }) {
    final now = _now();
    _db.execute(
      '''UPDATE review_attempts
         SET status = ?, session_id = ?, score = ?, result_json = ?,
             completed_at = ?, updated_at = ?
         WHERE id = ? AND deleted_at IS NULL''',
      [
        status,
        sessionId,
        score,
        result == null ? null : jsonEncode(result),
        now,
        now,
        attemptId,
      ],
    );
    unawaited(_sync?.syncReviewAttempt(attemptId));
  }

  ReviewPlanRecord? planById(String id) {
    final rows = _db.select(
      'SELECT * FROM review_plans WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return rows.isEmpty ? null : _planFromRow(rows.first);
  }

  /// Hydrates a plan downloaded from Supabase without enqueueing another
  /// upload. The timestamp guard preserves a newer offline edit on this
  /// device while still restoring plans missing after an install.
  void upsertPlanFromRemote(Map<String, dynamic> row) {
    final now = _now();
    _db.execute(
      '''INSERT INTO review_plans
         (id, user_id, kind, requested_mode, resolved_mode, level_band, goal,
          duration_minutes, topic, source_fingerprint, brief_json,
          generated_json, status, created_at, updated_at, deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           user_id = excluded.user_id,
           kind = excluded.kind,
           requested_mode = excluded.requested_mode,
           resolved_mode = excluded.resolved_mode,
           level_band = excluded.level_band,
           goal = excluded.goal,
           duration_minutes = excluded.duration_minutes,
           topic = excluded.topic,
           source_fingerprint = excluded.source_fingerprint,
           brief_json = excluded.brief_json,
           generated_json = excluded.generated_json,
           status = excluded.status,
           updated_at = excluded.updated_at,
           deleted_at = excluded.deleted_at
         WHERE excluded.updated_at > review_plans.updated_at''',
      [
        _requiredText(row['id']),
        row['user_id'],
        _requiredText(row['kind'], fallback: 'review'),
        _requiredText(row['requested_mode'], fallback: 'smart'),
        _requiredText(row['resolved_mode'], fallback: 'smart'),
        _requiredText(row['level_band'], fallback: 'A2'),
        _text(row['goal']),
        (row['duration_minutes'] as num?)?.toInt() ?? 10,
        _text(row['topic']),
        _text(row['source_fingerprint']),
        _jsonText(row['brief_json']) ?? '{}',
        _jsonText(row['generated_json']),
        _requiredText(row['status'], fallback: 'planned'),
        _requiredText(row['created_at'], fallback: now),
        _requiredText(row['updated_at'], fallback: now),
        row['deleted_at'],
      ],
    );
  }

  void upsertTargetFromRemote(Map<String, dynamic> row) {
    final now = _now();
    _db.execute(
      '''INSERT INTO review_plan_targets
         (id, plan_id, target_key, target_type, display_text, reason,
          priority, source_ids_json, evidence_json, created_at, updated_at,
          deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           plan_id = excluded.plan_id,
           target_key = excluded.target_key,
           target_type = excluded.target_type,
           display_text = excluded.display_text,
           reason = excluded.reason,
           priority = excluded.priority,
           source_ids_json = excluded.source_ids_json,
           evidence_json = excluded.evidence_json,
           updated_at = excluded.updated_at,
           deleted_at = excluded.deleted_at
         WHERE excluded.updated_at > review_plan_targets.updated_at''',
      [
        _requiredText(row['id']),
        _requiredText(row['plan_id']),
        _text(row['target_key']),
        _text(row['target_type'], 'retrieval'),
        _text(row['display_text']),
        _text(row['reason']),
        (row['priority'] as num?)?.toDouble() ?? 0,
        _jsonText(row['source_ids_json']) ?? '[]',
        _jsonText(row['evidence_json']) ?? '{}',
        _requiredText(row['created_at'], fallback: now),
        _requiredText(row['updated_at'], fallback: now),
        row['deleted_at'],
      ],
    );
  }

  void upsertAttemptFromRemote(Map<String, dynamic> row) {
    final now = _now();
    _db.execute(
      '''INSERT INTO review_attempts
         (id, user_id, plan_id, activity_id, session_id, mode, status, score,
          result_json, started_at, completed_at, created_at, updated_at,
          deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           user_id = excluded.user_id,
           plan_id = excluded.plan_id,
           activity_id = excluded.activity_id,
           session_id = excluded.session_id,
           mode = excluded.mode,
           status = excluded.status,
           score = excluded.score,
           result_json = excluded.result_json,
           started_at = excluded.started_at,
           completed_at = excluded.completed_at,
           updated_at = excluded.updated_at,
           deleted_at = excluded.deleted_at
         WHERE excluded.updated_at > review_attempts.updated_at''',
      [
        _requiredText(row['id']),
        row['user_id'],
        _requiredText(row['plan_id']),
        row['activity_id'],
        row['session_id'],
        _requiredText(row['mode'], fallback: 'smart'),
        _requiredText(row['status'], fallback: 'started'),
        (row['score'] as num?)?.toDouble(),
        _jsonText(row['result_json']),
        _requiredText(row['started_at'], fallback: now),
        row['completed_at'],
        _requiredText(row['created_at'], fallback: now),
        _requiredText(row['updated_at'], fallback: now),
        row['deleted_at'],
      ],
    );
  }

  List<ReviewPlanRecord> recentPlans({String? kind, int limit = 10}) {
    final rows = kind == null
        ? _db.select(
            'SELECT * FROM review_plans WHERE deleted_at IS NULL '
            'ORDER BY created_at DESC LIMIT ?',
            [limit],
          )
        : _db.select(
            'SELECT * FROM review_plans WHERE kind = ? AND deleted_at IS NULL '
            'ORDER BY created_at DESC LIMIT ?',
            [kind, limit],
          );
    return rows.map(_planFromRow).toList(growable: false);
  }

  List<ReviewAttemptRecord> attemptsForPlan(String planId) {
    final rows = _db.select(
      'SELECT * FROM review_attempts WHERE plan_id = ? AND deleted_at IS NULL '
      'ORDER BY started_at DESC',
      [planId],
    );
    return rows.map(_attemptFromRow).toList(growable: false);
  }

  ReviewPlanRecord _planFromRow(Row row) => ReviewPlanRecord(
    id: row['id'] as String,
    kind: row['kind'] as String,
    requestedMode: row['requested_mode'] as String,
    resolvedMode: row['resolved_mode'] as String,
    levelBand: row['level_band'] as String,
    goal: row['goal'] as String,
    durationMinutes: row['duration_minutes'] as int,
    topic: row['topic'] as String,
    sourceFingerprint: row['source_fingerprint'] as String,
    brief: _decodeMap(row['brief_json']),
    generated: _decodeMap(row['generated_json']),
    status: row['status'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  ReviewAttemptRecord _attemptFromRow(Row row) => ReviewAttemptRecord(
    id: row['id'] as String,
    planId: row['plan_id'] as String,
    mode: row['mode'] as String,
    status: row['status'] as String,
    activityId: row['activity_id'] as String?,
    sessionId: row['session_id'] as String?,
    score: (row['score'] as num?)?.toDouble(),
    result: row['result_json'] == null ? null : _decodeMap(row['result_json']),
    startedAt: DateTime.parse(row['started_at'] as String),
    completedAt: row['completed_at'] == null
        ? null
        : DateTime.tryParse(row['completed_at'] as String),
  );

  static String _text(Object? value, [String fallback = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _requiredText(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _jsonText(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return jsonEncode(value);
  }

  static double _number(Object? value) => value is num ? value.toDouble() : 0;

  static List<String> _stringList(Object? value) => value is List
      ? value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList()
      : const [];

  static Map<String, dynamic> _decodeMap(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is! String || value.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
