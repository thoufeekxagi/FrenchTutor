import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../orchestration/models/competency.dart';
import '../../orchestration/models/error_event.dart';
import '../../orchestration/models/evidence_event.dart';
import '../../orchestration/models/task_result.dart';
import 'app_migrations.dart';

class DuplicateEventIdException implements Exception {
  const DuplicateEventIdException(this.table, this.id);

  final String table;
  final String id;

  @override
  String toString() => 'DuplicateEventIdException: $table already contains $id';
}

class EvidenceStore {
  EvidenceStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  void insertTaskResult(TaskResult result) {
    _db.execute('BEGIN');
    try {
      for (final event in result.competencyEvidence) {
        insertEvidence(event);
      }
      for (final error in result.errors) {
        insertError(error);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void insertEvidence(EvidenceEvent event) {
    _rejectDuplicate('evidence_events', event.id);
    _db.execute(
      '''INSERT INTO evidence_events
         (id, user_id, plan_id, plan_task_id, session_id, content_item_id,
          competency_id, modality, support_level, correctness, score,
          response_time_ms, attempt_number, evaluator, evaluator_confidence,
          response_json, error_codes_json, occurred_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        event.id,
        event.userId,
        event.planId,
        event.planTaskId,
        event.sessionId,
        event.contentItemId,
        event.competencyId,
        event.modality.wireName,
        event.supportLevel.wireName,
        event.correctness,
        event.score,
        event.responseTimeMs,
        event.attemptNumber,
        event.evaluator.wireName,
        event.evaluatorConfidence,
        event.response == null ? null : jsonEncode(event.response),
        jsonEncode(event.errorCodes),
        event.occurredAt.toUtc().toIso8601String(),
        event.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  List<EvidenceEvent> evidenceEvents({
    String? competencyId,
    String? contentItemId,
    String? planId,
    String? planTaskId,
    String? sessionId,
  }) {
    final filters = <String>[];
    final parameters = <Object?>[];
    _addFilter(filters, parameters, 'competency_id', competencyId);
    _addFilter(filters, parameters, 'content_item_id', contentItemId);
    _addFilter(filters, parameters, 'plan_id', planId);
    _addFilter(filters, parameters, 'plan_task_id', planTaskId);
    _addFilter(filters, parameters, 'session_id', sessionId);
    final where = filters.isEmpty ? '' : ' WHERE ${filters.join(' AND ')}';
    return _db
        .select(
          'SELECT * FROM evidence_events$where ORDER BY occurred_at, created_at, id',
          parameters,
        )
        .map(_evidenceFromRow)
        .toList(growable: false);
  }

  void insertError(ErrorEvent event) {
    if (!_contains('evidence_events', event.sourceEvidenceId)) {
      throw ArgumentError.value(
        event.sourceEvidenceId,
        'sourceEvidenceId',
        'must reference stored evidence',
      );
    }
    if (event.resolvedByEvidenceId case final resolutionId?) {
      if (!_contains('evidence_events', resolutionId)) {
        throw ArgumentError.value(
          resolutionId,
          'resolvedByEvidenceId',
          'must reference stored evidence',
        );
      }
    }
    _rejectDuplicate('error_events', event.id);
    _db.execute(
      '''INSERT INTO error_events
         (id, user_id, competency_id, source_evidence_id, error_code,
          observed_form, expected_form, explanation, severity, evaluator,
          evaluator_confidence, resolved_by_evidence_id, occurred_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        event.id,
        event.userId,
        event.competencyId,
        event.sourceEvidenceId,
        event.errorCode,
        event.observedForm,
        event.expectedForm,
        event.explanation,
        event.severity,
        event.evaluator.wireName,
        event.evaluatorConfidence,
        event.resolvedByEvidenceId,
        event.occurredAt.toUtc().toIso8601String(),
        event.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  List<ErrorEvent> errorEvents({
    String? competencyId,
    String? sourceEvidenceId,
    String? resolvedByEvidenceId,
  }) {
    final filters = <String>[];
    final parameters = <Object?>[];
    _addFilter(filters, parameters, 'competency_id', competencyId);
    _addFilter(filters, parameters, 'source_evidence_id', sourceEvidenceId);
    _addFilter(
      filters,
      parameters,
      'resolved_by_evidence_id',
      resolvedByEvidenceId,
    );
    final where = filters.isEmpty ? '' : ' WHERE ${filters.join(' AND ')}';
    return _db
        .select(
          'SELECT * FROM error_events$where ORDER BY occurred_at, created_at, id',
          parameters,
        )
        .map(_errorFromRow)
        .toList(growable: false);
  }

  void _rejectDuplicate(String table, String id) {
    if (_contains(table, id)) throw DuplicateEventIdException(table, id);
  }

  bool _contains(String table, String id) =>
      _db.select('SELECT 1 FROM $table WHERE id = ? LIMIT 1', [id]).isNotEmpty;
}

void _addFilter(
  List<String> filters,
  List<Object?> parameters,
  String column,
  String? value,
) {
  if (value == null) return;
  filters.add('$column = ?');
  parameters.add(value);
}

EvidenceEvent _evidenceFromRow(Row row) => EvidenceEvent(
  id: row['id'] as String,
  userId: row['user_id'] as String?,
  planId: row['plan_id'] as String?,
  planTaskId: row['plan_task_id'] as String?,
  sessionId: row['session_id'] as String?,
  contentItemId: row['content_item_id'] as String,
  competencyId: row['competency_id'] as String,
  modality: PerformanceModality.fromWireName(row['modality'] as String),
  supportLevel: EvidenceSupportLevel.fromWireName(
    row['support_level'] as String,
  ),
  correctness: (row['correctness'] as num?)?.toDouble(),
  score: (row['score'] as num?)?.toDouble(),
  responseTimeMs: row['response_time_ms'] as int?,
  attemptNumber: row['attempt_number'] as int,
  evaluator: EvidenceEvaluator.fromWireName(row['evaluator'] as String),
  evaluatorConfidence: (row['evaluator_confidence'] as num).toDouble(),
  response: _decodeMap(row['response_json'] as String?),
  errorCodes: List<String>.from(
    jsonDecode(row['error_codes_json'] as String) as List,
  ),
  occurredAt: DateTime.parse(row['occurred_at'] as String),
  createdAt: DateTime.parse(row['created_at'] as String),
);

ErrorEvent _errorFromRow(Row row) => ErrorEvent(
  id: row['id'] as String,
  userId: row['user_id'] as String?,
  competencyId: row['competency_id'] as String,
  sourceEvidenceId: row['source_evidence_id'] as String,
  errorCode: row['error_code'] as String,
  observedForm: row['observed_form'] as String?,
  expectedForm: row['expected_form'] as String?,
  explanation: row['explanation'] as String?,
  severity: (row['severity'] as num).toDouble(),
  evaluator: EvidenceEvaluator.fromWireName(row['evaluator'] as String),
  evaluatorConfidence: (row['evaluator_confidence'] as num).toDouble(),
  resolvedByEvidenceId: row['resolved_by_evidence_id'] as String?,
  occurredAt: DateTime.parse(row['occurred_at'] as String),
  createdAt: DateTime.parse(row['created_at'] as String),
);

Map<String, Object?>? _decodeMap(String? value) =>
    value == null ? null : (jsonDecode(value) as Map).cast<String, Object?>();
