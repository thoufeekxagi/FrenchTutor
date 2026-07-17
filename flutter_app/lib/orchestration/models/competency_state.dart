import '../twin/twin_updater.dart';
import 'competency.dart';

/// Cross-modal transfer states (plan section 7.3). Ordered roughly weakest
/// to strongest evidence; a transfer message must cite the real source task
/// that produced the upgrade, not just this label.
enum TransferStatus {
  notObserved('not_observed'),
  singleModality('single_modality'),
  crossModalSupported('cross_modal_supported'),
  crossModalProductive('cross_modal_productive'),
  spontaneousTransferObserved('spontaneous_transfer_observed');

  const TransferStatus(this.wireName);

  final String wireName;

  static TransferStatus fromWireName(String value) =>
      values.where((item) => item.wireName == value).firstOrNull ??
      (throw FormatException('Unknown transfer status: $value'));
}

/// Derived, rebuildable cache row (plan section 5.5). Never a source of
/// truth: any row here must be reproducible from `evidence_events` plus the
/// learner-model version that produced it.
class CompetencyState {
  const CompetencyState({
    required this.competencyId,
    required this.modality,
    required this.masteryEstimate,
    required this.confidence,
    required this.retentionStrength,
    required this.evidenceCount,
    required this.transferStatus,
    required this.learnerModelType,
    required this.modelVersion,
    this.userId,
    this.lastObservedAt,
    this.lastSuccessAt,
    this.nextReviewAt,
    this.modelState = const {},
  }) : assert(masteryEstimate >= 0 && masteryEstimate <= 1),
       assert(confidence >= 0 && confidence <= 1),
       assert(retentionStrength >= 0 && retentionStrength <= 1),
       assert(evidenceCount >= 0);

  final String? userId;
  final String competencyId;
  final PerformanceModality modality;
  final double masteryEstimate;
  final double confidence;
  final double retentionStrength;
  final int evidenceCount;
  final TransferStatus transferStatus;
  final DateTime? lastObservedAt;
  final DateTime? lastSuccessAt;
  final DateTime? nextReviewAt;
  final String learnerModelType;
  final String modelVersion;
  final Map<String, Object?> modelState;

  bool get needsMoreEvidence => evidenceCount < 3 || confidence < 0.35;

  bool dueForReview(DateTime now) =>
      nextReviewAt != null && !nextReviewAt!.isAfter(now);

  factory CompetencyState.fromBelief({
    required CompetencyBeliefState belief,
    required double retentionStrength,
    required TransferStatus transferStatus,
    required DateTime? nextReviewAt,
    required DateTime? lastSuccessAt,
    String? userId,
    String learnerModelType = 'contextual_bkt',
  }) => CompetencyState(
    userId: userId,
    competencyId: belief.competencyId,
    modality: belief.modality,
    masteryEstimate: belief.pKnown,
    confidence: belief.confidence,
    retentionStrength: retentionStrength,
    evidenceCount: belief.evidenceCount,
    transferStatus: transferStatus,
    lastObservedAt: belief.lastObservedAt,
    lastSuccessAt: lastSuccessAt,
    nextReviewAt: nextReviewAt,
    learnerModelType: learnerModelType,
    modelVersion: belief.modelVersion,
  );
}
