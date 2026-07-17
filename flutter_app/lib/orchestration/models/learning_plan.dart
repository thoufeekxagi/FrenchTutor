import 'dart:collection';

import 'plan_task.dart';

enum PlanSnapshotStatus {
  generated,
  inProgress,
  completed,
  replaced;

  static PlanSnapshotStatus fromWireName(String value) =>
      values.where((item) => item.name == value).firstOrNull ??
      (throw FormatException('Unknown plan snapshot status: $value'));
}

/// An immutable daily plan (plan section 5.6 / 8.7). Generated once from a
/// [PlanningContext] and a policy version; starting any task locks it.
/// Replanning creates a new [PlanSnapshot] linked via [replacesPlanId] — it
/// never rewrites a prior one.
class PlanSnapshot {
  PlanSnapshot({
    required this.id,
    required this.localDate,
    required this.availableMinutes,
    required this.primaryPriority,
    required this.explanation,
    required this.plannerVersion,
    required this.status,
    this.userId,
    Map<String, Object?> environment = const {},
    Map<String, Object?> inputSnapshot = const {},
    List<PlanTaskRecord> tasks = const [],
    this.replacesPlanId,
    this.replanReason,
    this.startedAt,
    this.completedAt,
  }) : environment = UnmodifiableMapView(Map<String, Object?>.of(environment)),
       inputSnapshot = UnmodifiableMapView(
         Map<String, Object?>.of(inputSnapshot),
       ),
       tasks = UnmodifiableListView(List<PlanTaskRecord>.of(tasks)) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (availableMinutes < 0) {
      throw ArgumentError.value(
        availableMinutes,
        'availableMinutes',
        'must be >= 0',
      );
    }
  }

  final String id;
  final String? userId;
  final String localDate;
  final int availableMinutes;
  final Map<String, Object?> environment;
  final String primaryPriority;
  final String explanation;
  final String plannerVersion;
  final Map<String, Object?> inputSnapshot;
  final PlanSnapshotStatus status;
  final String? replacesPlanId;
  final String? replanReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<PlanTaskRecord> tasks;

  int get totalMinutes =>
      tasks.fold(0, (sum, task) => sum + task.estimatedMinutes);

  bool get isLocked =>
      status == PlanSnapshotStatus.inProgress ||
      status == PlanSnapshotStatus.completed;
}
