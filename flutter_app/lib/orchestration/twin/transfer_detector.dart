import 'dart:collection';

import '../models/competency.dart';
import '../models/competency_state.dart';
import '../models/evidence_event.dart';

/// [TransferStatus] plus the real evidence ids that justify it — the plan
/// requires transfer messages to cite real source tasks, not just assert a
/// label (section 7.3).
class TransferDetectionResult {
  TransferDetectionResult({
    required this.status,
    List<String> citedEvidenceIds = const [],
  }) : citedEvidenceIds = UnmodifiableListView(
         List<String>.of(citedEvidenceIds),
       );

  final TransferStatus status;
  final List<String> citedEvidenceIds;
}

/// Detects cross-modal transfer for one competency from its raw evidence,
/// deterministically and without inventing unobserved claims (invariant in
/// plan section 7.2: "Reading evidence does not automatically update
/// spontaneous speaking").
class TransferDetector {
  const TransferDetector({this.successThreshold = 0.6});

  final double successThreshold;

  TransferDetectionResult detect({
    required String competencyId,
    required Iterable<EvidenceEvent> evidence,
  }) {
    final relevant =
        evidence.where((event) => event.competencyId == competencyId).toList()
          ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (relevant.isEmpty) {
      return TransferDetectionResult(status: TransferStatus.notObserved);
    }

    final spontaneous = relevant.where(
      (event) =>
          event.supportLevel == EvidenceSupportLevel.spontaneousTransfer &&
          _isSuccess(event),
    );
    if (spontaneous.isNotEmpty) {
      return TransferDetectionResult(
        status: TransferStatus.spontaneousTransferObserved,
        citedEvidenceIds: spontaneous.map((event) => event.id).toList(),
      );
    }

    final modalities = relevant.map((event) => event.modality).toSet();
    if (modalities.length < 2) {
      return TransferDetectionResult(status: TransferStatus.singleModality);
    }

    final firstModality = relevant.first.modality;
    final productiveElsewhere = relevant.where(
      (event) =>
          event.supportLevel == EvidenceSupportLevel.unaidedProduction &&
          event.modality != firstModality &&
          _isSuccess(event),
    );
    if (productiveElsewhere.isNotEmpty) {
      return TransferDetectionResult(
        status: TransferStatus.crossModalProductive,
        citedEvidenceIds: productiveElsewhere.map((event) => event.id).toList(),
      );
    }

    return TransferDetectionResult(status: TransferStatus.crossModalSupported);
  }

  bool _isSuccess(EvidenceEvent event) =>
      (event.correctness ?? event.score ?? 0) >= successThreshold;
}
