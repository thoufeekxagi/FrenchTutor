import 'dart:collection';

import 'error_event.dart';
import 'evidence_event.dart';

enum TaskResultStatus {
  completed,
  skipped,
  abandoned,
  failed;

  static TaskResultStatus fromWireName(String value) =>
      values.where((item) => item.name == value).firstOrNull ??
      (throw FormatException('Unknown task result status: $value'));
}

class TaskResult {
  TaskResult({
    required this.status,
    required this.attempts,
    required this.learnerVisibleFeedback,
    List<EvidenceEvent> competencyEvidence = const [],
    List<ErrorEvent> errors = const [],
    Map<String, Object?> technicalMetadata = const {},
  }) : competencyEvidence = UnmodifiableListView(
         List<EvidenceEvent>.of(competencyEvidence),
       ),
       errors = UnmodifiableListView(List<ErrorEvent>.of(errors)),
       technicalMetadata = UnmodifiableMapView(
         Map<String, Object?>.of(technicalMetadata),
       ) {
    if (attempts < 0) {
      throw ArgumentError.value(attempts, 'attempts', 'must be >= 0');
    }
  }

  final TaskResultStatus status;
  final int attempts;
  final List<EvidenceEvent> competencyEvidence;
  final List<ErrorEvent> errors;
  final String learnerVisibleFeedback;
  final Map<String, Object?> technicalMetadata;
}
