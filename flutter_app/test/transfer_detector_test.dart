import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/competency_state.dart';
import 'package:french_tutor/orchestration/models/evidence_event.dart';
import 'package:french_tutor/orchestration/twin/transfer_detector.dart';

void main() {
  const detector = TransferDetector();
  final occurredAt = DateTime.utc(2026, 3, 1);

  EvidenceEvent event({
    required String id,
    required PerformanceModality modality,
    required EvidenceSupportLevel support,
    double correctness = 1,
    DateTime? at,
  }) => EvidenceEvent(
    id: id,
    contentItemId: 'content-$id',
    competencyId: 'competency',
    modality: modality,
    supportLevel: support,
    correctness: correctness,
    evaluator: EvidenceEvaluator.deterministicExact,
    evaluatorConfidence: 0.9,
    occurredAt: at ?? occurredAt,
    createdAt: at ?? occurredAt,
  );

  test('reports notObserved with no evidence for the competency', () {
    final result = detector.detect(competencyId: 'competency', evidence: const []);
    expect(result.status, TransferStatus.notObserved);
    expect(result.citedEvidenceIds, isEmpty);
  });

  test('reports singleModality when only one modality has evidence', () {
    final result = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'a',
          modality: PerformanceModality.readingRecognition,
          support: EvidenceSupportLevel.recognition,
        ),
      ],
    );
    expect(result.status, TransferStatus.singleModality);
  });

  test('reports crossModalSupported for weak evidence across modalities', () {
    final result = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'a',
          modality: PerformanceModality.readingRecognition,
          support: EvidenceSupportLevel.recognition,
        ),
        event(
          id: 'b',
          modality: PerformanceModality.listeningRecognition,
          support: EvidenceSupportLevel.cuedRecall,
        ),
      ],
    );
    expect(result.status, TransferStatus.crossModalSupported);
  });

  test('reports crossModalProductive and cites the productive evidence', () {
    final result = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'a',
          modality: PerformanceModality.readingRecognition,
          support: EvidenceSupportLevel.recognition,
          at: occurredAt,
        ),
        event(
          id: 'b',
          modality: PerformanceModality.controlledSpeaking,
          support: EvidenceSupportLevel.unaidedProduction,
          correctness: 0.9,
          at: occurredAt.add(const Duration(days: 1)),
        ),
      ],
    );
    expect(result.status, TransferStatus.crossModalProductive);
    expect(result.citedEvidenceIds, ['b']);
  });

  test('does not credit an unaided success that fell below threshold', () {
    final result = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'a',
          modality: PerformanceModality.readingRecognition,
          support: EvidenceSupportLevel.recognition,
        ),
        event(
          id: 'b',
          modality: PerformanceModality.controlledSpeaking,
          support: EvidenceSupportLevel.unaidedProduction,
          correctness: 0.2,
        ),
      ],
    );
    expect(result.status, TransferStatus.crossModalSupported);
  });

  test('a hinted writing success does not unlock transfer the way unaided does', () {
    // Mirrors the writing() adapter's hint-aware demotion: reusing today's
    // vocab correctly in writing only counts as proof of transfer if it was
    // produced without leaning on the hint ladder first.
    final hinted = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'read',
          modality: PerformanceModality.readingRecognition,
          support: EvidenceSupportLevel.recognition,
          at: occurredAt,
        ),
        event(
          id: 'write-hinted',
          modality: PerformanceModality.controlledWriting,
          support: EvidenceSupportLevel.hintedProduction,
          correctness: 0.9,
          at: occurredAt.add(const Duration(days: 1)),
        ),
      ],
    );
    expect(hinted.status, TransferStatus.crossModalSupported);

    final unaided = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'read',
          modality: PerformanceModality.readingRecognition,
          support: EvidenceSupportLevel.recognition,
          at: occurredAt,
        ),
        event(
          id: 'write-unaided',
          modality: PerformanceModality.controlledWriting,
          support: EvidenceSupportLevel.unaidedProduction,
          correctness: 0.9,
          at: occurredAt.add(const Duration(days: 1)),
        ),
      ],
    );
    expect(unaided.status, TransferStatus.crossModalProductive);
    expect(unaided.citedEvidenceIds, ['write-unaided']);
  });

  test('spontaneous transfer evidence outranks everything else', () {
    final result = detector.detect(
      competencyId: 'competency',
      evidence: [
        event(
          id: 'a',
          modality: PerformanceModality.spontaneousSpeaking,
          support: EvidenceSupportLevel.spontaneousTransfer,
          correctness: 0.8,
        ),
      ],
    );
    expect(result.status, TransferStatus.spontaneousTransferObserved);
    expect(result.citedEvidenceIds, ['a']);
  });
}
