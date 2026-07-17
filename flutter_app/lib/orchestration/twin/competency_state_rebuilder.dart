import '../models/competency_state.dart';
import '../models/content_descriptor.dart';
import '../models/evidence_event.dart';
import 'evidence_observation_adapter.dart';
import 'retention_policy.dart';
import 'transfer_detector.dart';
import 'twin_updater.dart';

/// Rebuilds the full derived-state cache (plan section 5.5 / 7 step 10) from
/// the append-only evidence ledger. Same ordered events + same model version
/// always produce the same [CompetencyState] list — this is the invariant
/// the persistence layer relies on to safely discard and recompute the
/// cache at any time.
class CompetencyStateRebuilder {
  const CompetencyStateRebuilder({
    this.adapter = const EvidenceObservationAdapter(),
    this.retentionPolicy = const RetentionPolicy(),
    this.transferDetector = const TransferDetector(),
    this.successThreshold = 0.6,
  });

  final EvidenceObservationAdapter adapter;
  final RetentionPolicy retentionPolicy;
  final TransferDetector transferDetector;
  final double successThreshold;

  List<CompetencyState> rebuild({
    required CompetencyFramework framework,
    required Iterable<EvidenceEvent> evidence,
    String? userId,
    LearnerStateModel? model,
  }) {
    final learnerModel = model ?? O3ProbabilisticLearnerModel();
    final observations = adapter.convert(evidence: evidence, framework: framework);
    final beliefs = learnerModel.rebuild(observations);
    final evidenceList = evidence.toList(growable: false);
    final transferByCompetency = <String, TransferDetectionResult>{};

    return beliefs.values
        .map((belief) {
          final transfer = transferByCompetency.putIfAbsent(
            belief.competencyId,
            () => transferDetector.detect(
              competencyId: belief.competencyId,
              evidence: evidenceList,
            ),
          );
          final lastSuccessAt = evidenceList
              .where(
                (event) =>
                    event.competencyId == belief.competencyId &&
                    event.modality == belief.modality &&
                    (event.correctness ?? event.score ?? 0) >= successThreshold,
              )
              .map((event) => event.occurredAt)
              .fold<DateTime?>(
                null,
                (latest, at) =>
                    latest == null || at.isAfter(latest) ? at : latest,
              );
          return CompetencyState.fromBelief(
            belief: belief,
            retentionStrength: retentionPolicy.retentionStrength(belief),
            transferStatus: transfer.status,
            nextReviewAt: retentionPolicy.nextReviewAt(belief),
            lastSuccessAt: lastSuccessAt,
            userId: userId,
          );
        })
        .toList(growable: false);
  }
}
