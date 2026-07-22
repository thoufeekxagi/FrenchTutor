import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/evidence/evaluator_confidence_policy.dart';
import 'package:french_tutor/orchestration/evidence/task_result_adapters.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/models/evidence_event.dart';
import 'package:french_tutor/orchestration/models/task_result.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 3, 1, 12);
  final createdAt = DateTime.utc(2026, 3, 1, 12, 1);
  var nextId = 0;
  late TaskResultAdapters adapters;

  setUp(() {
    nextId = 0;
    adapters = TaskResultAdapters(
      framework: _framework,
      idFactory: () => 'event-${nextId++}',
      clock: () => createdAt,
    );
  });

  TaskEvidenceContext context([
    TaskResultStatus status = TaskResultStatus.completed,
  ]) => TaskEvidenceContext(
    sessionId: 'session-1',
    status: status,
    occurredAt: occurredAt,
  );

  test('vocabulary preserves attempts without inventing correctness', () {
    final result = adapters.vocabulary(
      context: context(),
      reviewedContentItemIds: ['word-1'],
    );

    expect(result.attempts, 1);
    expect(result.competencyEvidence, hasLength(1));
    expect(result.competencyEvidence.single.correctness, isNull);
    expect(result.competencyEvidence.single.response, {
      'signal': 'reviewed_without_grade',
    });
    expect(result.technicalMetadata['masterySignal'], isFalse);
  });

  test('grammar preserves each graded attempt and applies confidence cap', () {
    final result = adapters.grammar(
      context: context(TaskResultStatus.abandoned),
      contentItemId: 'grammar-1',
      drillResults: [true, false],
    );

    expect(result.status, TaskResultStatus.abandoned);
    expect(result.attempts, 2);
    expect(result.competencyEvidence.map((event) => event.correctness), [1, 0]);
    expect(result.competencyEvidence.map((event) => event.attemptNumber), [
      1,
      2,
    ]);
    expect(result.competencyEvidence.first.evaluatorConfidence, 0.55);
  });

  test('listening withholds ungraded traversal from mastery evidence', () {
    final result = adapters.listening(
      context: context(),
      contentItemId: 'listen-1',
      correct: 2,
      attempted: 2,
      objectivelyGraded: false,
    );

    expect(result.attempts, 2);
    expect(result.competencyEvidence, isEmpty);
    expect(
      result.technicalMetadata['evidenceWithheld'],
      'result_not_objectively_graded',
    );
  });

  test('objectively graded listening emits exact bounded evidence', () {
    final result = adapters.listening(
      context: context(),
      contentItemId: 'listen-1',
      correct: 1,
      attempted: 2,
      objectivelyGraded: true,
    );

    expect(result.competencyEvidence.map((event) => event.correctness), [1, 0]);
    expect(result.competencyEvidence.first.evaluatorConfidence, 0.95);
  });

  test('writing normalizes rubric score and caps LLM confidence', () {
    final result = adapters.writing(
      context: context(),
      contentItemId: 'write-1',
      scoreOutOf10: 8.5,
    );

    final event = result.competencyEvidence.single;
    expect(event.score, 0.85);
    expect(event.correctness, 0.85);
    expect(event.evaluator, EvidenceEvaluator.llmTextRubric);
    expect(event.evaluatorConfidence, 0.65);
    expect(event.supportLevel, EvidenceSupportLevel.unaidedProduction);
    expect(result.technicalMetadata['hintsUsed'], 0);
  });

  test('writing demotes support level once the hint ladder was used', () {
    final result = adapters.writing(
      context: context(),
      contentItemId: 'write-1',
      scoreOutOf10: 9,
      hintsUsed: 2,
    );

    final event = result.competencyEvidence.single;
    expect(event.supportLevel, EvidenceSupportLevel.hintedProduction);
    expect(event.response!['hintsUsed'], 2);
    expect(result.technicalMetadata['hintsUsed'], 2);
  });

  test('writing rejects a negative hint count', () {
    expect(
      () => adapters.writing(
        context: context(),
        contentItemId: 'write-1',
        scoreOutOf10: 9,
        hintsUsed: -1,
      ),
      throwsArgumentError,
    );
  });

  test('speaking engagement explicitly emits no mastery evidence', () {
    final result = adapters.speaking(
      context: context(),
      contentItemId: 'speak-1',
      learnerUtteranceCount: 4,
      durationSeconds: 75,
    );

    expect(result.attempts, 4);
    expect(result.competencyEvidence, isEmpty);
    expect(
      result.technicalMetadata['evidenceWithheld'],
      'engagement_does_not_measure_language_quality',
    );
  });

  test('unmapped content withholds evidence instead of throwing', () {
    // Content with no competency mapping (e.g. arbitrary rotated content
    // outside the curated competency graph) degrades gracefully — the task
    // itself still completes, evidence just isn't minted for it.
    final result = adapters.grammar(
      context: context(),
      contentItemId: 'unknown',
      drillResults: [true],
    );
    expect(result.competencyEvidence, isEmpty);
    expect(result.technicalMetadata['evidenceWithheld'], 'no_competency_mapping');
  });

  test('invalid evaluator confidence is rejected', () {
    expect(
      () => const EvaluatorConfidencePolicy().cap(
        EvidenceEvaluator.selfReport,
        1.1,
      ),
      throwsArgumentError,
    );
  });
}

const _framework = CompetencyFramework(
  frameworkVersion: 'test',
  curriculumVersion: 'test',
  competencies: [
    Competency(
      id: 'lexical',
      kind: CompetencyKind.lexical,
      title: 'Lexical',
      description: 'Lexical',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
    Competency(
      id: 'grammar',
      kind: CompetencyKind.grammar,
      title: 'Grammar',
      description: 'Grammar',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
    Competency(
      id: 'listening',
      kind: CompetencyKind.strategy,
      title: 'Listening',
      description: 'Listening',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
    Competency(
      id: 'writing',
      kind: CompetencyKind.discourse,
      title: 'Writing',
      description: 'Writing',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
    Competency(
      id: 'speaking',
      kind: CompetencyKind.function,
      title: 'Speaking',
      description: 'Speaking',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
  ],
  mappings: [
    ContentCompetencyMapping(
      id: 'map-word',
      contentItemId: 'word-1',
      competencyId: 'lexical',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.readingRecognition,
      weight: 0.7,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'map-grammar',
      contentItemId: 'grammar-1',
      competencyId: 'grammar',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.controlledSpeaking,
      weight: 0.7,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'map-listening',
      contentItemId: 'listen-1',
      competencyId: 'listening',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.listeningRecognition,
      weight: 0.9,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'map-writing',
      contentItemId: 'write-1',
      competencyId: 'writing',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.controlledWriting,
      weight: 0.8,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'map-speaking',
      contentItemId: 'speak-1',
      competencyId: 'speaking',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.spontaneousSpeaking,
      weight: 0.9,
      curriculumVersion: 'test',
    ),
  ],
);
