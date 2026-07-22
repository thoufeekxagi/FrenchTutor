import 'package:uuid/uuid.dart';

import '../../data/content_service.dart';
import '../../data/database/learning_store.dart';
import '../../data/database/plan_store.dart';
import '../models/competency.dart';
import '../models/learning_plan.dart';
import '../models/mission.dart';
import '../models/plan_reason.dart';
import '../models/plan_task.dart';

const _uuid = Uuid();

/// Fixed daily rotation: one content type at a time, no competency graph,
/// no level-window filtering, no mastery scoring. Freshness comes from (a)
/// a different modality every day and (b) never repeating a content item
/// until the whole bank for that modality has actually been seen once —
/// this is the simple version the founder asked for, replacing the
/// validated mission-catalog system it sits alongside but no longer feeds.
///
/// [PerformanceModality.controlledSpeaking] is used for the grammar slot
/// (paired with `isGrammarPractice: true` on its step, which is what
/// routes it to the grammar-drill screen in `MissionTaskExecutor` rather
/// than a live roleplay call) and [PerformanceModality.spontaneousSpeaking]
/// for the roleplay slot — the same two enum values `MissionTaskExecutor`
/// already discriminates on today, just chosen here instead of picked from
/// a catalog.
const rotationOrder = [
  PerformanceModality.listeningRecognition,
  PerformanceModality.readingRecognition,
  PerformanceModality.controlledSpeaking,
  PerformanceModality.spontaneousSpeaking,
  PerformanceModality.controlledWriting,
];

/// How many vocab words make up one reading/vocab rotation day — a single
/// word ("just the word I") reads as broken; `MissionTaskExecutor._runVocabulary`
/// already batches every sibling pending `readingRecognition` task in the
/// same plan into one screen visit, so this just needs to hand it several.
const vocabBatchSize = 8;

class RotationPlan {
  const RotationPlan({required this.plan, required this.mission});

  final PlanSnapshot plan;
  final MissionDefinition mission;
}

class RotationPlanner {
  const RotationPlanner();

  RotationPlan buildNext({
    required PlanStore planStore,
    required LearningStore learningStore,
    required ContentService content,
    required String localDate,
    required int availableMinutes,
    required String learnerLevel,
    String? userId,
    String? replacesPlanId,
    String? replanReason,
  }) {
    final index =
        planStore.totalPlanCount(userId: userId) % rotationOrder.length;
    final modality = rotationOrder[index];
    final seen = learningStore.allLessonProgress().keys.toSet();
    final pool = _poolFor(content, modality);
    if (pool.isEmpty) {
      throw StateError('No content available for $modality');
    }
    final contentItemIds = modality == PerformanceModality.readingRecognition
        ? _pickMany(pool, seen, vocabBatchSize)
        : [_pickOne(pool, seen)];

    final mission = buildMissionFor(
      contentItemIds: contentItemIds,
      modality: modality,
      learnerLevel: learnerLevel,
    );

    final planId = _uuid.v4();
    final tasks = [
      for (final (i, contentItemId) in contentItemIds.indexed)
        PlanTaskRecord(
          // A real UUID, matching how the catalog-based planner mints task
          // ids (orchestration_service.dart) — plan_task_state.id is a
          // Postgres `uuid` column; the previous composite string
          // ('${planId}_task_$i') isn't valid uuid syntax and made every
          // rotation-plan task's sync push fail outright.
          id: _uuid.v4(),
          userId: userId,
          planId: planId,
          sequence: i,
          contentItemId: contentItemId,
          modality: modality,
          requirement: PlanTaskRequirement.must,
          estimatedMinutes: (availableMinutes / contentItemIds.length).round(),
          reasonCode: PlanReasonCode.learnerChoice,
          status: PlanTaskStatus.pending,
        ),
    ];

    final plan = PlanSnapshot(
      id: planId,
      userId: userId,
      localDate: localDate,
      availableMinutes: availableMinutes,
      primaryPriority: modality.wireName,
      explanation: _explanationFor(modality),
      plannerVersion: 'rotation-v1',
      status: PlanSnapshotStatus.generated,
      inputSnapshot: {'modality': modality.wireName},
      tasks: tasks,
      replacesPlanId: replacesPlanId,
      replanReason: replanReason,
    );
    return RotationPlan(plan: plan, mission: mission);
  }

  /// Rebuilds the same ad-hoc mission from a persisted task alone — needed
  /// when the app restarts mid-day and reloads today's plan from
  /// [PlanStore] rather than generating a fresh one. Deterministic and pure
  /// (no randomness, no DB read) so it always reconstructs identically.
  MissionDefinition buildMissionFor({
    required List<String> contentItemIds,
    required PerformanceModality modality,
    required String learnerLevel,
  }) {
    final title = _titleFor(modality);
    final isGrammar = modality == PerformanceModality.controlledSpeaking;
    return MissionDefinition(
      id: 'rotation_${modality.wireName}',
      title: title,
      scenario: _explanationFor(modality),
      levelBand: learnerLevel.toUpperCase(),
      primaryCompetencyId: 'rotation',
      promptContext:
          'The learner is practicing at level ${learnerLevel.toUpperCase()}. '
          'Keep the pace simple, encouraging, and appropriate to that level.',
      steps: [
        for (final (i, contentItemId) in contentItemIds.indexed)
          MissionStepDefinition(
            id: 'rotation_step_$i',
            contentItemId: contentItemId,
            modality: modality,
            estimatedMinutes: 10,
            evidenceGoal: _evidenceGoalFor(modality),
            isGrammarPractice: isGrammar,
            // NOT the roleplay path (that needs a speaking topic elsewhere in
            // the same mission's steps, via MissionTaskExecutor._missionTopic
            // — a rotation mission is always single-modality, so that lookup
            // always fails and threw "Mission ... has no speaking context"
            // every single time this slot came up). Plain listening
            // comprehension (MissionTaskExecutor._runGeneratedStoryReading)
            // needs no speaking topic and is the correct fit here.
          ),
      ],
    );
  }

  String _pickOne(List<String> pool, Set<String> seen) =>
      _pickMany(pool, seen, 1).first;

  List<String> _pickMany(List<String> pool, Set<String> seen, int count) {
    final unseen = pool.where((id) => !seen.contains(id)).toList();
    // The whole bank for this modality has been seen — cycle back to the
    // start rather than erroring or refusing to serve anything.
    final candidates = unseen.isNotEmpty ? unseen : pool;
    return candidates.take(count).toList();
  }

  List<String> _poolFor(ContentService content, PerformanceModality modality) {
    switch (modality) {
      case PerformanceModality.listeningRecognition:
        return content.listening()?.exercises.map((e) => e.id).toList() ??
            const [];
      case PerformanceModality.readingRecognition:
        return content.vocabPhases
            .expand((phase) => phase.themes)
            .expand((theme) => theme.entries)
            .map((entry) => entry.id)
            .toList();
      case PerformanceModality.controlledSpeaking:
        return content.grammar()?.lessons.map((l) => l.id).toList() ??
            const [];
      case PerformanceModality.spontaneousSpeaking:
        return content.resources()?.speakingTopics
                .map((t) => t.id)
                .toList() ??
            const [];
      case PerformanceModality.controlledWriting:
        return content.writingTasks()?.tasks.map((t) => t.id).toList() ??
            const [];
      default:
        return const [];
    }
  }

  String _titleFor(PerformanceModality modality) => switch (modality) {
    PerformanceModality.listeningRecognition => 'Listening practice',
    PerformanceModality.readingRecognition => 'Vocabulary practice',
    PerformanceModality.controlledSpeaking => 'Grammar practice',
    PerformanceModality.spontaneousSpeaking => 'Roleplay practice',
    PerformanceModality.controlledWriting => 'Writing practice',
    _ => 'Practice',
  };

  String _explanationFor(PerformanceModality modality) => switch (modality) {
    PerformanceModality.listeningRecognition =>
      'Today rotates to listening — a fresh passage to understand.',
    PerformanceModality.readingRecognition =>
      'Today rotates to vocabulary — new words to recognise.',
    PerformanceModality.controlledSpeaking =>
      'Today rotates to grammar — a point worth practicing aloud.',
    PerformanceModality.spontaneousSpeaking =>
      'Today rotates to roleplay — a short live conversation.',
    PerformanceModality.controlledWriting =>
      'Today rotates to writing — a short passage to compose.',
    _ => 'Today\'s practice.',
  };

  String _evidenceGoalFor(PerformanceModality modality) => switch (modality) {
    PerformanceModality.listeningRecognition => 'Understand a short passage.',
    PerformanceModality.readingRecognition => 'Recognise today\'s words.',
    PerformanceModality.controlledSpeaking => 'Practice today\'s grammar point.',
    PerformanceModality.spontaneousSpeaking => 'Have a short conversation.',
    PerformanceModality.controlledWriting => 'Write a short passage.',
    _ => 'Practice.',
  };
}
