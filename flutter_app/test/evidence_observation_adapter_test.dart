import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/models/evidence_event.dart';
import 'package:french_tutor/orchestration/twin/evidence_observation_adapter.dart';

void main() {
  test(
    'converts graded evidence in stable order and skips exposure-only events',
    () {
      final later = DateTime.utc(2026, 3, 3);
      final earlier = DateTime.utc(2026, 3, 1);
      final observations = const EvidenceObservationAdapter().convert(
        evidence: [
          _event('later', later, correctness: 0, attempt: 2),
          _event('exposure', earlier, correctness: null),
          _event('earlier', earlier, correctness: 1),
        ],
        framework: _framework,
      );

      expect(observations, hasLength(2));
      expect(observations.first.correctness, 1);
      expect(observations.first.elapsed, Duration.zero);
      expect(observations.last.correctness, 0);
      expect(observations.last.elapsed, const Duration(days: 2));
      expect(observations.last.reliability, closeTo(0.6 / 1.15, 0.0001));
      expect(observations.last.genuineLearningOpportunity, isTrue);
    },
  );

  test('rejects graded evidence without an authoritative mapping', () {
    expect(
      () => const EvidenceObservationAdapter().convert(
        evidence: [
          EvidenceEvent(
            id: 'unknown',
            contentItemId: 'unknown',
            competencyId: 'competency',
            modality: PerformanceModality.controlledWriting,
            supportLevel: EvidenceSupportLevel.cuedRecall,
            correctness: 1,
            evaluator: EvidenceEvaluator.deterministicExact,
            evaluatorConfidence: 0.9,
            occurredAt: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
          ),
        ],
        framework: _framework,
      ),
      throwsStateError,
    );
  });
}

EvidenceEvent _event(
  String id,
  DateTime occurredAt, {
  required double? correctness,
  int attempt = 1,
}) => EvidenceEvent(
  id: id,
  contentItemId: 'content',
  competencyId: 'competency',
  modality: PerformanceModality.controlledWriting,
  supportLevel: EvidenceSupportLevel.cuedRecall,
  correctness: correctness,
  attemptNumber: attempt,
  evaluator: EvidenceEvaluator.llmAudioCoaching,
  evaluatorConfidence: 0.55,
  occurredAt: occurredAt,
  createdAt: occurredAt,
);

const _framework = CompetencyFramework(
  frameworkVersion: 'test',
  curriculumVersion: 'test',
  competencies: [
    Competency(
      id: 'competency',
      kind: CompetencyKind.grammar,
      title: 'Competency',
      description: 'Competency',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
  ],
  mappings: [
    ContentCompetencyMapping(
      id: 'mapping',
      contentItemId: 'content',
      competencyId: 'competency',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.controlledWriting,
      weight: 0.8,
      curriculumVersion: 'test',
    ),
  ],
);
