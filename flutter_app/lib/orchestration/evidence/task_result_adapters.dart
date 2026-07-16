import 'package:uuid/uuid.dart';

import '../models/competency.dart';
import '../models/content_descriptor.dart';
import '../models/evidence_event.dart';
import '../models/task_result.dart';
import 'evaluator_confidence_policy.dart';

typedef EvidenceIdFactory = String Function();

class TaskEvidenceContext {
  const TaskEvidenceContext({
    required this.sessionId,
    required this.status,
    required this.occurredAt,
    this.userId,
    this.planId,
    this.planTaskId,
  });

  final String? userId;
  final String? planId;
  final String? planTaskId;
  final String sessionId;
  final TaskResultStatus status;
  final DateTime occurredAt;
}

class TaskResultAdapters {
  TaskResultAdapters({
    required this.framework,
    this.confidencePolicy = const EvaluatorConfidencePolicy(),
    EvidenceIdFactory? idFactory,
    DateTime Function()? clock,
  }) : _idFactory = idFactory ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final CompetencyFramework framework;
  final EvaluatorConfidencePolicy confidencePolicy;
  final EvidenceIdFactory _idFactory;
  final DateTime Function() _clock;

  bool supports(String contentItemId, PerformanceModality modality) =>
      framework.mappings.any(
        (mapping) =>
            mapping.contentItemId == contentItemId &&
            mapping.modality == modality,
      );

  TaskResult vocabulary({
    required TaskEvidenceContext context,
    required List<String> reviewedContentItemIds,
  }) {
    final evidence = <EvidenceEvent>[];
    for (final contentItemId in reviewedContentItemIds) {
      final mapping = _mapping(
        contentItemId,
        PerformanceModality.readingRecognition,
      );
      evidence.add(
        _event(
          context: context,
          mapping: mapping,
          supportLevel: EvidenceSupportLevel.recognition,
          evaluator: EvidenceEvaluator.deterministicRule,
          proposedConfidence: 0.85,
          attemptNumber: 1,
          response: const {'signal': 'reviewed_without_grade'},
        ),
      );
    }
    return TaskResult(
      status: context.status,
      attempts: reviewedContentItemIds.length,
      learnerVisibleFeedback: reviewedContentItemIds.isEmpty
          ? 'No vocabulary attempts recorded.'
          : 'Vocabulary practice recorded.',
      competencyEvidence: evidence,
      technicalMetadata: {
        'adapter': 'vocabulary_v1',
        'confidencePolicyVersion': confidencePolicy.version,
        'masterySignal': false,
      },
    );
  }

  TaskResult grammar({
    required TaskEvidenceContext context,
    required String contentItemId,
    required List<bool> drillResults,
  }) {
    final mapping = _mapping(
      contentItemId,
      PerformanceModality.controlledSpeaking,
    );
    final evidence = [
      for (final (index, correct) in drillResults.indexed)
        _event(
          context: context,
          mapping: mapping,
          supportLevel: EvidenceSupportLevel.cuedRecall,
          evaluator: EvidenceEvaluator.llmAudioCoaching,
          proposedConfidence: 0.80,
          correctness: correct ? 1 : 0,
          attemptNumber: index + 1,
          response: {'drillIndex': index, 'correct': correct},
        ),
    ];
    return TaskResult(
      status: context.status,
      attempts: drillResults.length,
      learnerVisibleFeedback: drillResults.isEmpty
          ? 'No grammar attempts recorded.'
          : 'Grammar practice recorded.',
      competencyEvidence: evidence,
      technicalMetadata: {
        'adapter': 'grammar_v1',
        'confidencePolicyVersion': confidencePolicy.version,
      },
    );
  }

  TaskResult listening({
    required TaskEvidenceContext context,
    required String contentItemId,
    required int correct,
    required int attempted,
    required bool objectivelyGraded,
  }) {
    if (correct < 0 || attempted < 0 || correct > attempted) {
      throw ArgumentError(
        'Listening counts must satisfy 0 <= correct <= attempted',
      );
    }
    if (!objectivelyGraded) {
      return TaskResult(
        status: context.status,
        attempts: attempted,
        learnerVisibleFeedback: attempted == 0
            ? 'No listening attempts recorded.'
            : 'Listening practice recorded.',
        technicalMetadata: {
          'adapter': 'listening_v1',
          'contentItemId': contentItemId,
          'confidencePolicyVersion': confidencePolicy.version,
          'evidenceWithheld': 'result_not_objectively_graded',
        },
      );
    }
    final mapping = _mapping(
      contentItemId,
      PerformanceModality.listeningRecognition,
    );
    final evidence = [
      for (var index = 0; index < attempted; index++)
        _event(
          context: context,
          mapping: mapping,
          supportLevel: EvidenceSupportLevel.recognition,
          evaluator: EvidenceEvaluator.deterministicExact,
          proposedConfidence: 0.95,
          correctness: index < correct ? 1 : 0,
          attemptNumber: index + 1,
          response: {'questionIndex': index},
        ),
    ];
    return TaskResult(
      status: context.status,
      attempts: attempted,
      learnerVisibleFeedback: 'Listening result recorded.',
      competencyEvidence: evidence,
      technicalMetadata: {
        'adapter': 'listening_v1',
        'confidencePolicyVersion': confidencePolicy.version,
      },
    );
  }

  TaskResult writing({
    required TaskEvidenceContext context,
    required String contentItemId,
    required double? scoreOutOf10,
  }) {
    if (scoreOutOf10 != null &&
        (!scoreOutOf10.isFinite || scoreOutOf10 < 0 || scoreOutOf10 > 10)) {
      throw ArgumentError.value(
        scoreOutOf10,
        'scoreOutOf10',
        'must be between 0 and 10',
      );
    }
    final evidence = <EvidenceEvent>[];
    if (scoreOutOf10 != null) {
      final mapping = _mapping(
        contentItemId,
        PerformanceModality.controlledWriting,
      );
      evidence.add(
        _event(
          context: context,
          mapping: mapping,
          supportLevel: EvidenceSupportLevel.unaidedProduction,
          evaluator: EvidenceEvaluator.llmTextRubric,
          proposedConfidence: 0.80,
          score: scoreOutOf10 / 10,
          correctness: scoreOutOf10 / 10,
          attemptNumber: 1,
          response: {'scoreOutOf10': scoreOutOf10},
        ),
      );
    }
    return TaskResult(
      status: context.status,
      attempts: scoreOutOf10 == null ? 0 : 1,
      learnerVisibleFeedback: scoreOutOf10 == null
          ? 'No graded writing attempt recorded.'
          : 'Writing feedback recorded.',
      competencyEvidence: evidence,
      technicalMetadata: {
        'adapter': 'writing_v1',
        'confidencePolicyVersion': confidencePolicy.version,
      },
    );
  }

  TaskResult speaking({
    required TaskEvidenceContext context,
    required String contentItemId,
    required int learnerUtteranceCount,
    required int durationSeconds,
  }) {
    if (learnerUtteranceCount < 0 || durationSeconds < 0) {
      throw ArgumentError('Speaking counts must not be negative');
    }
    _mapping(contentItemId, PerformanceModality.spontaneousSpeaking);
    return TaskResult(
      status: context.status,
      attempts: learnerUtteranceCount,
      learnerVisibleFeedback: learnerUtteranceCount == 0
          ? 'No speaking attempt recorded.'
          : 'Speaking practice recorded.',
      technicalMetadata: {
        'adapter': 'speaking_v1',
        'contentItemId': contentItemId,
        'durationSeconds': durationSeconds,
        'confidencePolicyVersion': confidencePolicy.version,
        'evidenceWithheld': 'engagement_does_not_measure_language_quality',
      },
    );
  }

  ContentCompetencyMapping _mapping(
    String contentItemId,
    PerformanceModality modality,
  ) {
    final matches = framework.mappings.where(
      (mapping) =>
          mapping.contentItemId == contentItemId &&
          mapping.modality == modality,
    );
    if (matches.length != 1) {
      throw StateError(
        'Expected one $modality mapping for $contentItemId, found ${matches.length}',
      );
    }
    return matches.single;
  }

  EvidenceEvent _event({
    required TaskEvidenceContext context,
    required ContentCompetencyMapping mapping,
    required EvidenceSupportLevel supportLevel,
    required EvidenceEvaluator evaluator,
    required double proposedConfidence,
    required int attemptNumber,
    double? correctness,
    double? score,
    Map<String, Object?>? response,
  }) => EvidenceEvent(
    id: _idFactory(),
    userId: context.userId,
    planId: context.planId,
    planTaskId: context.planTaskId,
    sessionId: context.sessionId,
    contentItemId: mapping.contentItemId,
    competencyId: mapping.competencyId,
    modality: mapping.modality,
    supportLevel: supportLevel,
    correctness: correctness,
    score: score,
    attemptNumber: attemptNumber,
    evaluator: evaluator,
    evaluatorConfidence: confidencePolicy.cap(evaluator, proposedConfidence),
    response: response,
    occurredAt: context.occurredAt,
    createdAt: _clock(),
  );
}
