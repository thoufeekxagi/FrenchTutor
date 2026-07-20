import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../orchestration/models/competency.dart';
import '../../orchestration/models/competency_state.dart';
import '../../services/sync_service.dart';
import 'app_migrations.dart';

const _uuid = Uuid();

/// Persists the rebuildable `learner_competency_states` cache (plan section
/// 5.5). This store never derives beliefs itself — callers rebuild with
/// `CompetencyStateRebuilder` from the evidence ledger and hand the result
/// here to be replaced wholesale, so the cache can never drift from its
/// source of truth.
class CompetencyStateStore {
  CompetencyStateStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  String _now() => DateTime.now().toUtc().toIso8601String();

  /// Replaces every cached state for [userId] with [states]. Safe to call
  /// repeatedly with a freshly rebuilt list — this is a cache, not history.
  void replaceAll(String? userId, List<CompetencyState> states) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'DELETE FROM learner_competency_states WHERE user_id IS ?',
        [userId],
      );
      for (final state in states) {
        final now = _now();
        _db.execute(
          '''INSERT INTO learner_competency_states
             (id, user_id, competency_id, modality, mastery_estimate,
              confidence, retention_strength, evidence_count, transfer_status,
              last_observed_at, last_success_at, next_review_at,
              learner_model_type, model_version, model_state_json,
              created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            _uuid.v4(),
            userId,
            state.competencyId,
            state.modality.wireName,
            state.masteryEstimate,
            state.confidence,
            state.retentionStrength,
            state.evidenceCount,
            state.transferStatus.wireName,
            state.lastObservedAt?.toUtc().toIso8601String(),
            state.lastSuccessAt?.toUtc().toIso8601String(),
            state.nextReviewAt?.toUtc().toIso8601String(),
            state.learnerModelType,
            state.modelVersion,
            jsonEncode(state.modelState),
            now,
            now,
          ],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    unawaited(_sync?.syncCompetencyStates(states));
  }

  List<CompetencyState> all({String? userId}) => _db
      .select(
        'SELECT * FROM learner_competency_states WHERE user_id IS ? AND deleted_at IS NULL '
        'ORDER BY competency_id, modality',
        [userId],
      )
      .map(_fromRow)
      .toList(growable: false);

  CompetencyState? byCompetency({
    required String competencyId,
    required PerformanceModality modality,
    String? userId,
  }) {
    final rows = _db.select(
      'SELECT * FROM learner_competency_states '
      'WHERE user_id IS ? AND competency_id = ? AND modality = ? AND deleted_at IS NULL',
      [userId, competencyId, modality.wireName],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  List<CompetencyState> dueForReview({String? userId, DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).toUtc().toIso8601String();
    return _db
        .select(
          'SELECT * FROM learner_competency_states '
          'WHERE user_id IS ? AND deleted_at IS NULL AND next_review_at IS NOT NULL AND next_review_at <= ? '
          'ORDER BY next_review_at',
          [userId, cutoff],
        )
        .map(_fromRow)
        .toList(growable: false);
  }

  CompetencyState _fromRow(Row row) => CompetencyState(
    userId: row['user_id'] as String?,
    competencyId: row['competency_id'] as String,
    modality: PerformanceModality.fromWireName(row['modality'] as String),
    masteryEstimate: (row['mastery_estimate'] as num).toDouble(),
    confidence: (row['confidence'] as num).toDouble(),
    retentionStrength: (row['retention_strength'] as num).toDouble(),
    evidenceCount: row['evidence_count'] as int,
    transferStatus: TransferStatus.fromWireName(
      row['transfer_status'] as String,
    ),
    lastObservedAt: _parseDate(row['last_observed_at']),
    lastSuccessAt: _parseDate(row['last_success_at']),
    nextReviewAt: _parseDate(row['next_review_at']),
    learnerModelType: row['learner_model_type'] as String,
    modelVersion: row['model_version'] as String,
    modelState: (jsonDecode(row['model_state_json'] as String) as Map)
        .cast<String, Object?>(),
  );
}

DateTime? _parseDate(Object? raw) =>
    raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
