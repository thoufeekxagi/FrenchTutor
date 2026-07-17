import '../models/competency_state.dart';
import '../models/error_event.dart';
import '../twin/retention_policy.dart';
import 'orchestrator.dart';

/// Projects the per-modality [CompetencyState] cache and open [ErrorEvent]s
/// into the coarser, per-competency [PlanningContext] the planner scores
/// against. Kept separate from the planner itself so the projection rule
/// (how modalities average, how "recent" is defined) has one owner.
class PlannerContextBuilder {
  const PlannerContextBuilder({
    this.retentionPolicy = const RetentionPolicy(),
    this.recentErrorWindow = const Duration(days: 14),
  });

  final RetentionPolicy retentionPolicy;
  final Duration recentErrorWindow;

  PlanningContext build({
    required int availableMinutes,
    required bool canSpeakAloud,
    required bool networkAvailable,
    required String goal,
    required List<CompetencyState> competencyStates,
    List<ErrorEvent> errors = const [],
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final byCompetency = <String, List<CompetencyState>>{};
    for (final state in competencyStates) {
      byCompetency.putIfAbsent(state.competencyId, () => []).add(state);
    }

    final plannerStates = byCompetency.entries
        .map((entry) {
          final states = entry.value;
          final belief =
              states.fold<double>(0, (sum, s) => sum + s.masteryEstimate) /
              states.length;
          final confidence =
              states.fold<double>(0, (sum, s) => sum + s.confidence) /
              states.length;
          final dueForReview = states.any(
            (s) => s.nextReviewAt != null && !s.nextReviewAt!.isAfter(at),
          );
          final recentErrors = errors
              .where(
                (error) =>
                    error.competencyId == entry.key &&
                    error.resolvedByEvidenceId == null &&
                    !error.occurredAt.isBefore(at.subtract(recentErrorWindow)),
              )
              .length;
          return PlannerCompetencyState(
            competencyId: entry.key,
            belief: belief,
            uncertainty: (1 - confidence).clamp(0, 1).toDouble(),
            dueForReview: dueForReview,
            recentErrors: recentErrors,
          );
        })
        .toList(growable: false);

    return PlanningContext(
      availableMinutes: availableMinutes,
      canSpeakAloud: canSpeakAloud,
      networkAvailable: networkAvailable,
      goal: goal,
      competencyStates: plannerStates,
    );
  }
}
