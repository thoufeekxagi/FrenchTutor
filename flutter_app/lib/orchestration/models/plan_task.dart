import 'dart:collection';

import 'competency.dart';
import 'plan_reason.dart';

enum PlanTaskRequirement {
  must,
  should,
  bonus;

  static PlanTaskRequirement fromWireName(String value) =>
      values.where((item) => item.name == value).firstOrNull ??
      (throw FormatException('Unknown plan task requirement: $value'));
}

enum PlanTaskStatus {
  pending,
  active,
  completed,
  skipped;

  static PlanTaskStatus fromWireName(String value) =>
      values.where((item) => item.name == value).firstOrNull ??
      (throw FormatException('Unknown plan task status: $value'));
}

/// A single row of an immutable [PlanSnapshot] (plan section 5.7). Persisted
/// verbatim once its plan is generated; only `status`/`startedAt`/
/// `completedAt`/`resultSummary` change as the learner works through it.
class PlanTaskRecord {
  PlanTaskRecord({
    required this.id,
    required this.planId,
    required this.sequence,
    required this.contentItemId,
    required this.modality,
    required this.requirement,
    required this.estimatedMinutes,
    required this.reasonCode,
    required this.status,
    this.userId,
    Map<String, Object?> reasonDetail = const {},
    List<String> targetCompetencyIds = const [],
    this.startedAt,
    this.completedAt,
    Map<String, Object?>? resultSummary,
  }) : reasonDetail = UnmodifiableMapView(
         Map<String, Object?>.of(reasonDetail),
       ),
       targetCompetencyIds = UnmodifiableListView(
         List<String>.of(targetCompetencyIds),
       ),
       resultSummary = resultSummary == null
           ? null
           : UnmodifiableMapView(Map<String, Object?>.of(resultSummary)) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (estimatedMinutes < 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'must be >= 0',
      );
    }
  }

  final String id;
  final String? userId;
  final String planId;
  final int sequence;
  final String contentItemId;
  final PerformanceModality modality;
  final PlanTaskRequirement requirement;
  final int estimatedMinutes;
  final PlanReasonCode reasonCode;
  final Map<String, Object?> reasonDetail;
  final List<String> targetCompetencyIds;
  final PlanTaskStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Map<String, Object?>? resultSummary;

  PlanTaskRecord copyWith({
    PlanTaskStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    Map<String, Object?>? resultSummary,
  }) => PlanTaskRecord(
    id: id,
    userId: userId,
    planId: planId,
    sequence: sequence,
    contentItemId: contentItemId,
    modality: modality,
    requirement: requirement,
    estimatedMinutes: estimatedMinutes,
    reasonCode: reasonCode,
    reasonDetail: reasonDetail,
    targetCompetencyIds: targetCompetencyIds,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    resultSummary: resultSummary ?? this.resultSummary,
  );
}
