import '../models/content_descriptor.dart';
import 'orchestrator.dart';

/// Deterministic offline default (plan section 8.8 "baseline" floor and
/// 13.1 "network-dependent AI tasks show a clear queued or unavailable
/// state"). Used when there is no learner-state estimate yet or AI/network
/// is unavailable — picks straightforward, no-network, no-live-speaking
/// review/introduction tasks so a learner is never blocked from practising.
class FallbackPlanFactory {
  const FallbackPlanFactory({this.maxTasks = 4});

  final int maxTasks;

  LearningPlan build({
    required CompetencyFramework framework,
    required int availableMinutes,
  }) {
    final competencies = {
      for (final competency in framework.competencies) competency.id: competency,
    };
    final candidates = framework.mappings
        .where((mapping) => isOfflineSafeModality(mapping.modality))
        .toList()
      ..sort((a, b) {
        final competency = a.competencyId.compareTo(b.competencyId);
        if (competency != 0) return competency;
        return a.contentItemId.compareTo(b.contentItemId);
      });

    final selected = <PlanTask>[];
    final seenContent = <String>{};
    var totalMinutes = 0;
    for (final mapping in candidates) {
      final competency = competencies[mapping.competencyId];
      if (competency == null || seenContent.contains(mapping.contentItemId)) {
        continue;
      }
      final minutes = minutesForModality(mapping.modality);
      if (totalMinutes + minutes > availableMinutes) continue;
      selected.add(
        PlanTask(
          contentItemId: mapping.contentItemId,
          competencyId: mapping.competencyId,
          modality: mapping.modality,
          role: mapping.role,
          estimatedMinutes: minutes,
          priority: PlanPriority.should,
          score: mapping.weight,
          reasonTrace: const [
            PlanReasonTrace(
              reason: PlanningReason.mappingStrength,
              contribution: 1,
            ),
          ],
        ),
      );
      seenContent.add(mapping.contentItemId);
      totalMinutes += minutes;
      if (selected.length >= maxTasks) break;
    }

    return LearningPlan(
      tasks: List.unmodifiable(selected),
      totalMinutes: totalMinutes,
      availableMinutes: availableMinutes,
    );
  }
}
