import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/competency_state.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/models/evidence_event.dart';
import 'package:french_tutor/orchestration/twin/competency_state_rebuilder.dart';

const _framework = CompetencyFramework(
  frameworkVersion: 'test',
  curriculumVersion: 'test',
  competencies: [
    Competency(
      id: 'competency',
      kind: CompetencyKind.lexical,
      title: 'Word',
      description: 'A word',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
  ],
  mappings: [
    ContentCompetencyMapping(
      id: 'mapping-reading',
      contentItemId: 'content-reading',
      competencyId: 'competency',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.readingRecognition,
      weight: 0.8,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'mapping-speaking',
      contentItemId: 'content-speaking',
      competencyId: 'competency',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.controlledSpeaking,
      weight: 0.9,
      curriculumVersion: 'test',
    ),
  ],
);

List<EvidenceEvent> _evidence() {
  final base = DateTime.utc(2026, 3, 1);
  return [
    EvidenceEvent(
      id: 'evidence-1',
      contentItemId: 'content-reading',
      competencyId: 'competency',
      modality: PerformanceModality.readingRecognition,
      supportLevel: EvidenceSupportLevel.recognition,
      correctness: 1,
      evaluator: EvidenceEvaluator.deterministicExact,
      evaluatorConfidence: 0.95,
      occurredAt: base,
      createdAt: base,
    ),
    EvidenceEvent(
      id: 'evidence-2',
      contentItemId: 'content-reading',
      competencyId: 'competency',
      modality: PerformanceModality.readingRecognition,
      supportLevel: EvidenceSupportLevel.recognition,
      correctness: 1,
      evaluator: EvidenceEvaluator.deterministicExact,
      evaluatorConfidence: 0.95,
      occurredAt: base.add(const Duration(days: 1)),
      createdAt: base.add(const Duration(days: 1)),
    ),
    EvidenceEvent(
      id: 'evidence-3',
      contentItemId: 'content-speaking',
      competencyId: 'competency',
      modality: PerformanceModality.controlledSpeaking,
      supportLevel: EvidenceSupportLevel.unaidedProduction,
      correctness: 0.9,
      evaluator: EvidenceEvaluator.llmAudioCoaching,
      evaluatorConfidence: 0.7,
      occurredAt: base.add(const Duration(days: 2)),
      createdAt: base.add(const Duration(days: 2)),
    ),
  ];
}

void main() {
  const rebuilder = CompetencyStateRebuilder();

  test('rebuilds one state per competency/modality with real evidence counts', () {
    final states = rebuilder.rebuild(framework: _framework, evidence: _evidence());

    expect(states, hasLength(2));
    final reading = states.firstWhere(
      (s) => s.modality == PerformanceModality.readingRecognition,
    );
    final speaking = states.firstWhere(
      (s) => s.modality == PerformanceModality.controlledSpeaking,
    );
    expect(reading.evidenceCount, 2);
    expect(speaking.evidenceCount, 1);
    expect(reading.masteryEstimate, inInclusiveRange(0, 1));
    expect(reading.confidence, inInclusiveRange(0, 1));
    expect(reading.lastSuccessAt, isNotNull);
  });

  test('same ordered evidence always rebuilds to the same posterior', () {
    final first = rebuilder.rebuild(framework: _framework, evidence: _evidence());
    final second = rebuilder.rebuild(framework: _framework, evidence: _evidence());

    for (var i = 0; i < first.length; i++) {
      expect(second[i].masteryEstimate, first[i].masteryEstimate);
      expect(second[i].confidence, first[i].confidence);
      expect(second[i].evidenceCount, first[i].evidenceCount);
      expect(second[i].transferStatus, first[i].transferStatus);
    }
  });

  test('detects cross-modal productive transfer across the two modalities', () {
    final states = rebuilder.rebuild(framework: _framework, evidence: _evidence());
    for (final state in states) {
      expect(state.transferStatus, TransferStatus.crossModalProductive);
    }
  });
}
