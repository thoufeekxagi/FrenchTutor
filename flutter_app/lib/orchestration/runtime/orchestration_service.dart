import 'package:uuid/uuid.dart';

import '../../data/database/competency_state_store.dart';
import '../../data/database/evidence_store.dart';
import '../../data/database/plan_store.dart';
import '../models/competency_state.dart';
import '../models/content_descriptor.dart';
import '../models/error_event.dart';
import '../models/learning_plan.dart';
import '../models/mission.dart';
import '../models/plan_task.dart';
import '../planning/fallback_plan_factory.dart';
import '../planning/mission_plan_factory.dart';
import '../planning/mission_selector.dart';
import '../planning/orchestrator.dart';
import '../planning/plan_explainer.dart';
import '../planning/planner_context_builder.dart';
import '../twin/competency_state_rebuilder.dart';

const _uuid = Uuid();

/// The single call site that ties the twin updater, planner, and
/// persistence layers together (plan section 8/20.2 "keep one owner for
/// orchestration state"). This is additive: it reads/writes the
/// orchestration tables only and does not touch the shipped daily-pathway
/// navigation, so existing screens keep working unchanged while this is
/// exercised from the Orchestration Lab and future plan-executor work.
class OrchestrationService {
  const OrchestrationService({
    this.rebuilder = const CompetencyStateRebuilder(),
    this.contextBuilder = const PlannerContextBuilder(),
    this.orchestrator = const Orchestrator(),
    this.missionSelector = const MissionSelector(),
    this.missionPlanFactory = const MissionPlanFactory(),
    this.explainer = const PlanExplainer(),
    this.fallbackFactory = const FallbackPlanFactory(),
    this.plannerVersion = 'constrained-utility-v1',
  });

  final CompetencyStateRebuilder rebuilder;
  final PlannerContextBuilder contextBuilder;
  final Orchestrator orchestrator;
  final MissionSelector missionSelector;
  final MissionPlanFactory missionPlanFactory;
  final PlanExplainer explainer;
  final FallbackPlanFactory fallbackFactory;
  final String plannerVersion;

  /// Rebuilds the derived competency-state cache from the evidence ledger
  /// and replaces the persisted cache with it. Safe to call as often as
  /// needed — it is a pure function of the ledger, never additive.
  List<CompetencyState> refreshCompetencyStates({
    required CompetencyFramework framework,
    required EvidenceStore evidenceStore,
    required CompetencyStateStore stateStore,
    String? userId,
  }) {
    final states = rebuilder.rebuild(
      framework: framework,
      evidence: evidenceStore.evidenceEvents(),
      userId: userId,
    );
    stateStore.replaceAll(userId, states);
    return states;
  }

  /// Returns the plan already governing [localDate], generating and
  /// persisting one only if none exists yet — a started or completed plan
  /// is never silently regenerated (section 8.7).
  PlanSnapshot ensureTodayPlan({
    required CompetencyFramework framework,
    required List<CompetencyState> competencyStates,
    required List<ErrorEvent> errors,
    required PlanStore planStore,
    required String localDate,
    required int availableMinutes,
    required bool canSpeakAloud,
    required bool networkAvailable,
    required String goal,
    MissionCatalog? missionCatalog,
    String learnerLevel = 'a1',
    String? userId,
    bool difficultyBoost = false,
  }) {
    final existing = planStore.activePlanForDate(localDate, userId: userId);
    if (existing != null) return existing;

    // Never immediately repeat a mission from recent history if competency
    // scores haven't shifted yet — this is what made the daily mission feel
    // "stuck" on the same content. A 1-mission lookback was trivially
    // defeated by a small scenario pool, so this excludes recent history,
    // not just the single most recent mission — but scaled to the actual
    // catalog size, so a still-small catalog degrades gracefully (excluding
    // more missions than exist would empty the pool outright) rather than
    // breaking until the scenario bank is fully expanded.
    final nonCalibrationCount =
        missionCatalog?.missions.where((m) => !m.calibration).length ?? 0;
    final exclusionLimit = nonCalibrationCount > 1
        ? (nonCalibrationCount - 1).clamp(1, 40)
        : 0;
    final excludedMissionIds = exclusionLimit == 0
        ? const <String>{}
        : planStore
              .recentMissionIds(userId: userId, limit: exclusionLimit)
              .toSet();

    final snapshot = _generateSnapshot(
      framework: framework,
      competencyStates: competencyStates,
      errors: errors,
      localDate: localDate,
      availableMinutes: availableMinutes,
      canSpeakAloud: canSpeakAloud,
      networkAvailable: networkAvailable,
      goal: goal,
      missionCatalog: missionCatalog,
      learnerLevel: learnerLevel,
      userId: userId,
      excludedMissionIds: excludedMissionIds,
      difficultyBoost: difficultyBoost,
    );
    planStore.savePlan(snapshot);
    return snapshot;
  }

  /// Explicit "Replan today" (section 8.7): retires the current plan and
  /// persists a fresh one linked to it, recording why.
  PlanSnapshot replanToday({
    required CompetencyFramework framework,
    required List<CompetencyState> competencyStates,
    required List<ErrorEvent> errors,
    required PlanStore planStore,
    required PlanSnapshot current,
    required int availableMinutes,
    required bool canSpeakAloud,
    required bool networkAvailable,
    required String goal,
    required String reason,
    MissionCatalog? missionCatalog,
    String learnerLevel = 'a1',
    String? userId,
    Set<String> excludedMissionIds = const {},
    bool difficultyBoost = false,
  }) {
    // Merge the caller's explicit exclusion (e.g. "don't repeat the mission
    // that was just completed") with the same scaled recent-history window
    // ensureTodayPlan uses, so mid-day replans get the same non-repeat
    // guarantee as a fresh day's plan.
    final nonCalibrationCount =
        missionCatalog?.missions.where((m) => !m.calibration).length ?? 0;
    final exclusionLimit = nonCalibrationCount > 1
        ? (nonCalibrationCount - 1).clamp(1, 40)
        : 0;
    final recentIds = exclusionLimit == 0
        ? const <String>{}
        : planStore.recentMissionIds(userId: userId, limit: exclusionLimit).toSet();
    final next = _generateSnapshot(
      framework: framework,
      competencyStates: competencyStates,
      errors: errors,
      localDate: current.localDate,
      availableMinutes: availableMinutes,
      canSpeakAloud: canSpeakAloud,
      networkAvailable: networkAvailable,
      goal: goal,
      missionCatalog: missionCatalog,
      learnerLevel: learnerLevel,
      userId: userId,
      excludedMissionIds: {...excludedMissionIds, ...recentIds},
      difficultyBoost: difficultyBoost,
      replacesPlanId: current.id,
      replanReason: reason,
    );
    planStore.replan(replaces: current, newPlan: next);
    return next;
  }

  PlanSnapshot _generateSnapshot({
    required CompetencyFramework framework,
    required List<CompetencyState> competencyStates,
    required List<ErrorEvent> errors,
    required String localDate,
    required int availableMinutes,
    required bool canSpeakAloud,
    required bool networkAvailable,
    required String goal,
    MissionCatalog? missionCatalog,
    String learnerLevel = 'a1',
    String? userId,
    Set<String> excludedMissionIds = const {},
    bool difficultyBoost = false,
    String? replacesPlanId,
    String? replanReason,
  }) {
    final context = contextBuilder.build(
      availableMinutes: availableMinutes,
      canSpeakAloud: canSpeakAloud,
      networkAvailable: networkAvailable,
      goal: goal,
      competencyStates: competencyStates,
      errors: errors,
    );
    MissionRecommendation? mission;
    var runtimePlan = orchestrator.plan(framework: framework, context: context);
    if (missionCatalog != null) {
      mission = missionSelector.select(
        catalog: missionCatalog,
        level: learnerLevel,
        goal: goal,
        competencyStates: competencyStates,
        excludedMissionIds: excludedMissionIds,
        difficultyBoost: difficultyBoost,
      );
      final missionPlan = missionPlanFactory.build(
        framework: framework,
        recommendation: mission,
        context: context,
      );
      if (missionPlan.tasks.isNotEmpty) runtimePlan = missionPlan;
    }
    if (runtimePlan.tasks.isEmpty) {
      runtimePlan = fallbackFactory.build(
        framework: framework,
        availableMinutes: availableMinutes,
      );
    }

    final competencies = {
      for (final competency in framework.competencies)
        competency.id: competency,
    };
    final id = _uuid.v4();
    final taskRecords = <PlanTaskRecord>[];
    final explanations = <PlanExplanation>[];
    for (final (index, task) in runtimePlan.tasks.indexed) {
      final competency = competencies[task.competencyId];
      if (competency == null) continue;
      final explanation = explainer.explain(task: task, competency: competency);
      explanations.add(explanation);
      taskRecords.add(
        PlanTaskRecord(
          id: _uuid.v4(),
          userId: userId,
          planId: id,
          sequence: index,
          contentItemId: task.contentItemId,
          modality: task.modality,
          requirement: _toRequirement(task.priority),
          estimatedMinutes: task.estimatedMinutes,
          reasonCode: explanation.code,
          reasonDetail: {
            'score': task.score,
            'contributions': {
              for (final trace in task.reasonTrace)
                trace.reason.name: trace.contribution,
            },
          },
          targetCompetencyIds: [task.competencyId],
          status: PlanTaskStatus.pending,
        ),
      );
    }

    return PlanSnapshot(
      id: id,
      userId: userId,
      localDate: localDate,
      availableMinutes: runtimePlan.availableMinutes,
      environment: {
        'canSpeakAloud': canSpeakAloud,
        'networkAvailable': networkAvailable,
      },
      primaryPriority: explanations.isEmpty
          ? 'insufficient_evidence'
          : explanations.first.code.wireName,
      explanation:
          mission?.reason ??
          (explanations.isEmpty
              ? 'No eligible tasks fit the current time and context.'
              : explanations.first.text),
      plannerVersion: plannerVersion,
      inputSnapshot: {
        'goal': goal,
        'learnerLevel': learnerLevel,
        if (mission != null) ...{
          'missionId': mission.mission.id,
          'missionTitle': mission.mission.title,
          'missionScenario': mission.mission.scenario,
          'missionPromptContext': mission.mission.promptContext,
        },
      },
      status: PlanSnapshotStatus.generated,
      replacesPlanId: replacesPlanId,
      replanReason: replanReason,
      tasks: taskRecords,
    );
  }

  PlanTaskRequirement _toRequirement(PlanPriority priority) =>
      switch (priority) {
        PlanPriority.must => PlanTaskRequirement.must,
        PlanPriority.should => PlanTaskRequirement.should,
        PlanPriority.bonus => PlanTaskRequirement.bonus,
      };
}
