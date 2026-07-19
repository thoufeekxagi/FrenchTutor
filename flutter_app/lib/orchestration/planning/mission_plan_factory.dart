import '../models/competency.dart';
import '../models/content_descriptor.dart';
import '../models/mission.dart';
import 'mission_selector.dart';
import 'orchestrator.dart';

class MissionPlanFactory {
  const MissionPlanFactory();

  LearningPlan build({
    required CompetencyFramework framework,
    required MissionRecommendation recommendation,
    required PlanningContext context,
  }) {
    final mappings = {
      for (final mapping in framework.mappings)
        (mapping.contentItemId, mapping.modality): mapping,
    };
    final tasks = <PlanTask>[];
    var totalMinutes = 0;
    for (final step in recommendation.mission.steps) {
      if (!_canRun(step, context)) continue;
      if (totalMinutes + step.estimatedMinutes > context.availableMinutes) {
        continue;
      }
      final mapping = mappings[(step.contentItemId, step.modality)];
      if (mapping == null) {
        throw StateError(
          'Mission ${recommendation.mission.id} step ${step.id} is not mapped',
        );
      }
      tasks.add(
        PlanTask(
          contentItemId: step.contentItemId,
          competencyId: mapping.competencyId,
          modality: step.modality,
          role: mapping.role,
          estimatedMinutes: step.estimatedMinutes,
          priority: PlanPriority.should,
          score: mapping.weight,
          reasonTrace: const [
            PlanReasonTrace(
              reason: PlanningReason.goalAlignment,
              contribution: 1,
            ),
          ],
        ),
      );
      totalMinutes += step.estimatedMinutes;
    }
    return LearningPlan(
      tasks: List.unmodifiable(tasks),
      totalMinutes: totalMinutes,
      availableMinutes: context.availableMinutes,
    );
  }

  bool _canRun(MissionStepDefinition step, PlanningContext context) {
    final speaking = switch (step.modality) {
      PerformanceModality.controlledSpeaking ||
      PerformanceModality.spontaneousSpeaking ||
      PerformanceModality.pronunciationProduction => true,
      _ => false,
    };
    if (speaking && !context.canSpeakAloud) return false;
    return step.modality != PerformanceModality.spontaneousSpeaking ||
        context.networkAvailable;
  }
}
