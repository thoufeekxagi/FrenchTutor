import 'evidence_event.dart';

class ErrorEvent {
  ErrorEvent({
    required this.id,
    required this.competencyId,
    required this.sourceEvidenceId,
    required this.errorCode,
    required this.severity,
    required this.evaluator,
    required this.evaluatorConfidence,
    required this.occurredAt,
    required this.createdAt,
    this.userId,
    this.observedForm,
    this.expectedForm,
    this.explanation,
    this.resolvedByEvidenceId,
  }) {
    requireNonEmpty(id, 'id');
    requireNonEmpty(competencyId, 'competencyId');
    requireNonEmpty(sourceEvidenceId, 'sourceEvidenceId');
    requireNonEmpty(errorCode, 'errorCode');
    requireUnitInterval(severity, 'severity');
    requireUnitInterval(evaluatorConfidence, 'evaluatorConfidence');
  }

  final String id;
  final String? userId;
  final String competencyId;
  final String sourceEvidenceId;
  final String errorCode;
  final String? observedForm;
  final String? expectedForm;
  final String? explanation;
  final double severity;
  final EvidenceEvaluator evaluator;
  final double evaluatorConfidence;
  final String? resolvedByEvidenceId;
  final DateTime occurredAt;
  final DateTime createdAt;
}
