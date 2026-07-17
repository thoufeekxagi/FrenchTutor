import 'package:uuid/uuid.dart';

import '../../data/database/competency_state_store.dart';
import '../../data/database/evidence_store.dart';
import '../../data/database/plan_store.dart';
import '../models/competency_state.dart';
import '../models/content_descriptor.dart';
import '../models/error_event.dart';
import '../models/learning_plan.dart';
import '../models/plan_task.dart';
import '../planning/fallback_plan_factory.dart';
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
    this.explainer = const PlanExplainer(),
    this.fallbackFactory = const FallbackPlanFactory(),
    this.plannerVersion = 'constrained-utility-v1',
  });

  final CompetencyStateRebuilder rebuilder;
  final PlannerContextBuilder contextBuilder;
  final Orchestrator orchestrator;
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
    String? userId,
  }) {
    final existing = planStore.activePlanForDate(localDate, userId: userId);
    if (existing != null) return existing;

    final snapshot = _generateSnapshot(
      framework: framework,
      competencyStates: competencyStates,
      errors: errors,
      localDate: localDate,
      availableMinutes: availableMinutes,
      canSpeakAloud: canSpeakAloud,
      networkAvailable: networkAvailable,
      goal: goal,
      userId: userId,
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
    String? userId,
  }) {
    final next = _generateSnapshot(
      framework: framework,
      competencyStates: competencyStates,
      errors: errors,
      localDate: current.localDate,
      availableMinutes: availableMinutes,
      canSpeakAloud: canSpeakAloud,
      networkAvailable: networkAvailable,
      goal: goal,
      userId: userId,
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
    String? userId,
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
    var runtimePlan = orchestrator.plan(framework: framework, context: context);
    if (runtimePlan.tasks.isEmpty) {
      runtimePlan = fallbackFactory.build(
        framework: framework,
        availableMinutes: availableMinutes,
      );
    }

    final competencies = {
      for (final competency in framework.competencies) competency.id: competency,
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
      explanation: explanations.isEmpty
          ? 'No eligible tasks fit the current time and context.'
          : explanations.first.text,
      plannerVersion: plannerVersion,
      inputSnapshot: {'goal': goal},
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
