import '../models/competency.dart';
import '../models/content_descriptor.dart';

enum PlanPriority { must, should, bonus }

enum PlanningReason {
  dueReview,
  weakSkill,
  uncertainSkill,
  recentError,
  transferOpportunity,
  prerequisiteReadiness,
  goalAlignment,
  mappingStrength,
  contextPenalty,
  costPenalty,
}

class PlannerCompetencyState {
  const PlannerCompetencyState({
    required this.competencyId,
    required this.belief,
    this.uncertainty = 0,
    this.dueForReview = false,
    this.recentErrors = 0,
  }) : assert(belief >= 0 && belief <= 1),
       assert(uncertainty >= 0 && uncertainty <= 1),
       assert(recentErrors >= 0);

  final String competencyId;
  final double belief;
  final double uncertainty;
  final bool dueForReview;
  final int recentErrors;
}

class PlanningContext {
  const PlanningContext({
    required this.availableMinutes,
    required this.canSpeakAloud,
    required this.networkAvailable,
    required this.goal,
    this.competencyStates = const [],
  }) : assert(availableMinutes >= 0);

  final int availableMinutes;
  final bool canSpeakAloud;
  final bool networkAvailable;
  final String goal;
  final List<PlannerCompetencyState> competencyStates;
}

class PlanReasonTrace {
  const PlanReasonTrace({required this.reason, required this.contribution});

  final PlanningReason reason;
  final double contribution;
}

class PlanTask {
  const PlanTask({
    required this.contentItemId,
    required this.competencyId,
    required this.modality,
    required this.role,
    required this.estimatedMinutes,
    required this.priority,
    required this.score,
    required this.reasonTrace,
  });

  final String contentItemId;
  final String competencyId;
  final PerformanceModality modality;
  final ContentMappingRole role;
  final int estimatedMinutes;
  final PlanPriority priority;
  final double score;
  final List<PlanReasonTrace> reasonTrace;

  bool get isSpeaking => switch (modality) {
    PerformanceModality.controlledSpeaking ||
    PerformanceModality.spontaneousSpeaking ||
    PerformanceModality.pronunciationProduction => true,
    _ => false,
  };

  bool get requiresNetwork =>
      modality == PerformanceModality.spontaneousSpeaking;
}

class LearningPlan {
  const LearningPlan({
    required this.tasks,
    required this.totalMinutes,
    required this.availableMinutes,
  });

  final List<PlanTask> tasks;
  final int totalMinutes;
  final int availableMinutes;

  int get remainingMinutes => availableMinutes - totalMinutes;
}

abstract interface class TaskSelectionPolicy {
  LearningPlan select({
    required CompetencyFramework framework,
    required PlanningContext context,
  });
}

class ConstrainedUtilityPolicy implements TaskSelectionPolicy {
  const ConstrainedUtilityPolicy({this.prerequisiteThreshold = 0.65});

  final double prerequisiteThreshold;

  @override
  LearningPlan select({
    required CompetencyFramework framework,
    required PlanningContext context,
  }) {
    final competencies = {
      for (final competency in framework.competencies)
        competency.id: competency,
    };
    final states = {
      for (final state in context.competencyStates) state.competencyId: state,
    };
    final candidates = <PlanTask>[];

    for (final mapping in framework.mappings) {
      final competency = competencies[mapping.competencyId];
      if (competency == null ||
          !_prerequisitesReady(competency, states) ||
          !_contextAllows(mapping.modality, context)) {
        continue;
      }
      candidates.add(
        _candidate(
          mapping: mapping,
          competency: competency,
          state: states[competency.id],
          states: states,
          context: context,
        ),
      );
    }

    candidates.sort(_compareCandidates);
    final selected = <PlanTask>[];
    final selectedContent = <String>{};
    var totalMinutes = 0;
    for (final candidate in candidates) {
      if (selectedContent.contains(candidate.contentItemId) ||
          totalMinutes + candidate.estimatedMinutes >
              context.availableMinutes) {
        continue;
      }
      selected.add(candidate);
      selectedContent.add(candidate.contentItemId);
      totalMinutes += candidate.estimatedMinutes;
    }

    return LearningPlan(
      tasks: List.unmodifiable(selected),
      totalMinutes: totalMinutes,
      availableMinutes: context.availableMinutes,
    );
  }

  bool _prerequisitesReady(
    Competency competency,
    Map<String, PlannerCompetencyState> states,
  ) => competency.prerequisiteIds.every(
    (id) => (states[id]?.belief ?? 0) >= prerequisiteThreshold,
  );

  bool _contextAllows(PerformanceModality modality, PlanningContext context) {
    final speaking = switch (modality) {
      PerformanceModality.controlledSpeaking ||
      PerformanceModality.spontaneousSpeaking ||
      PerformanceModality.pronunciationProduction => true,
      _ => false,
    };
    if (speaking && !context.canSpeakAloud) return false;
    if (modality == PerformanceModality.spontaneousSpeaking &&
        !context.networkAvailable) {
      return false;
    }
    return true;
  }

  PlanTask _candidate({
    required ContentCompetencyMapping mapping,
    required Competency competency,
    required PlannerCompetencyState? state,
    required Map<String, PlannerCompetencyState> states,
    required PlanningContext context,
  }) {
    final belief = state?.belief ?? 0.5;
    final uncertainty = state?.uncertainty ?? 0.5;
    final minutes = _minutesFor(mapping.modality);
    final dueReview = state?.dueForReview == true ? 4.0 : 0.0;
    final weakSkill = belief < prerequisiteThreshold
        ? (prerequisiteThreshold - belief) * 5
        : 0.0;
    final uncertainSkill = uncertainty * 2;
    final recentError = ((state?.recentErrors ?? 0).clamp(0, 3)) * 1.5;
    final transferOpportunity = _isTransfer(mapping) ? 1.25 : 0.0;
    final prerequisiteReadiness = competency.prerequisiteIds.isEmpty
        ? 0.75
        : competency.prerequisiteIds
                  .map((id) => states[id]?.belief ?? 0)
                  .reduce((a, b) => a + b) /
              competency.prerequisiteIds.length;
    final normalizedGoal = context.goal.trim().toLowerCase();
    final goalAlignment =
        normalizedGoal.isNotEmpty &&
            ('${competency.id} ${competency.title} ${competency.description}'
                .toLowerCase()
                .contains(normalizedGoal))
        ? 2.0
        : 0.0;
    final mappingStrength = mapping.weight;
    final contextPenalty = _contextPenalty(mapping.modality, context);
    final costPenalty = -minutes * 0.08;
    final trace = <PlanReasonTrace>[
      PlanReasonTrace(
        reason: PlanningReason.dueReview,
        contribution: dueReview,
      ),
      PlanReasonTrace(
        reason: PlanningReason.weakSkill,
        contribution: weakSkill,
      ),
      PlanReasonTrace(
        reason: PlanningReason.uncertainSkill,
        contribution: uncertainSkill,
      ),
      PlanReasonTrace(
        reason: PlanningReason.recentError,
        contribution: recentError,
      ),
      PlanReasonTrace(
        reason: PlanningReason.transferOpportunity,
        contribution: transferOpportunity,
      ),
      PlanReasonTrace(
        reason: PlanningReason.prerequisiteReadiness,
        contribution: prerequisiteReadiness,
      ),
      PlanReasonTrace(
        reason: PlanningReason.goalAlignment,
        contribution: goalAlignment,
      ),
      PlanReasonTrace(
        reason: PlanningReason.mappingStrength,
        contribution: mappingStrength,
      ),
      PlanReasonTrace(
        reason: PlanningReason.contextPenalty,
        contribution: contextPenalty,
      ),
      PlanReasonTrace(
        reason: PlanningReason.costPenalty,
        contribution: costPenalty,
      ),
    ];
    final score = trace.fold<double>(0, (sum, item) => sum + item.contribution);

    return PlanTask(
      contentItemId: mapping.contentItemId,
      competencyId: mapping.competencyId,
      modality: mapping.modality,
      role: mapping.role,
      estimatedMinutes: minutes,
      priority: _priority(state, belief, uncertainty, goalAlignment),
      score: score,
      reasonTrace: List.unmodifiable(trace),
    );
  }

  PlanPriority _priority(
    PlannerCompetencyState? state,
    double belief,
    double uncertainty,
    double goalAlignment,
  ) {
    if (state?.dueForReview == true || (state?.recentErrors ?? 0) > 0) {
      return PlanPriority.must;
    }
    if (belief < prerequisiteThreshold ||
        uncertainty >= 0.35 ||
        goalAlignment > 0) {
      return PlanPriority.should;
    }
    return PlanPriority.bonus;
  }

  bool _isTransfer(ContentCompetencyMapping mapping) =>
      mapping.role == ContentMappingRole.assesses ||
      mapping.modality == PerformanceModality.spontaneousWriting ||
      mapping.modality == PerformanceModality.spontaneousSpeaking;

  double _contextPenalty(
    PerformanceModality modality,
    PlanningContext context,
  ) {
    if (context.availableMinutes <= 15 && _minutesFor(modality) >= 12) {
      return -1;
    }
    if (!context.networkAvailable &&
        modality == PerformanceModality.listeningRecognition) {
      return -0.25;
    }
    return 0;
  }

  int _compareCandidates(PlanTask a, PlanTask b) {
    final priority = a.priority.index.compareTo(b.priority.index);
    if (priority != 0) return priority;
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final competency = a.competencyId.compareTo(b.competencyId);
    if (competency != 0) return competency;
    final content = a.contentItemId.compareTo(b.contentItemId);
    if (content != 0) return content;
    return a.modality.index.compareTo(b.modality.index);
  }

  int _minutesFor(PerformanceModality modality) => minutesForModality(modality);
}

/// Authored per-modality time estimate. Shared by every policy — including
/// the offline [FallbackPlanFactory] — so a task's estimated length never
/// depends on which selector chose it.
int minutesForModality(PerformanceModality modality) => switch (modality) {
  PerformanceModality.listeningRecognition => 10,
  PerformanceModality.readingRecognition => 7,
  PerformanceModality.controlledWriting => 12,
  PerformanceModality.spontaneousWriting => 18,
  PerformanceModality.controlledSpeaking => 12,
  PerformanceModality.spontaneousSpeaking => 18,
  PerformanceModality.pronunciationProduction => 8,
};

/// True for tasks that can run with no network — every modality except
/// spontaneous (Gemini Live) speaking. Shared context-allow logic lives on
/// [ConstrainedUtilityPolicy._contextAllows]; this narrower helper is for
/// offline-only selection where there is no live [PlanningContext].
bool isOfflineSafeModality(PerformanceModality modality) =>
    modality != PerformanceModality.spontaneousSpeaking;

class Orchestrator {
  const Orchestrator({this.policy = const ConstrainedUtilityPolicy()});

  final TaskSelectionPolicy policy;

  LearningPlan plan({
    required CompetencyFramework framework,
    required PlanningContext context,
  }) => policy.select(framework: framework, context: context);
}
