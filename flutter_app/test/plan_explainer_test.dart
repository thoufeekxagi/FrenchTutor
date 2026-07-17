import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/models/plan_reason.dart';
import 'package:french_tutor/orchestration/planning/orchestrator.dart';
import 'package:french_tutor/orchestration/planning/plan_explainer.dart';

const _competency = Competency(
  id: 'competency-1',
  kind: CompetencyKind.grammar,
  title: 'Present tense of être',
  description: 'Conjugate être in the present tense.',
  difficultyBand: 'A2',
  prerequisiteIds: [],
  curriculumVersion: 'test',
);

PlanTask _task(List<PlanReasonTrace> trace, {PlanPriority priority = PlanPriority.must}) =>
    PlanTask(
      contentItemId: 'content-1',
      competencyId: 'competency-1',
      modality: PerformanceModality.controlledSpeaking,
      role: ContentMappingRole.practises,
      estimatedMinutes: 10,
      priority: priority,
      score: 3,
      reasonTrace: trace,
    );

void main() {
  const explainer = PlanExplainer();

  test('picks the highest-contributing positive reason', () {
    final result = explainer.explain(
      task: _task(const [
        PlanReasonTrace(reason: PlanningReason.dueReview, contribution: 4),
        PlanReasonTrace(reason: PlanningReason.weakSkill, contribution: 1),
        PlanReasonTrace(reason: PlanningReason.costPenalty, contribution: -1),
      ]),
      competency: _competency,
    );

    expect(result.code, PlanReasonCode.dueReview);
    expect(result.text, contains('Present tense of être'));
  });

  test('falls back to skillMaintenance when nothing contributes positively', () {
    final result = explainer.explain(
      task: _task(const [
        PlanReasonTrace(reason: PlanningReason.costPenalty, contribution: -1),
      ]),
      competency: _competency,
    );

    expect(result.code, PlanReasonCode.skillMaintenance);
  });

  test('mapping strength on a bonus task reads as learner choice', () {
    final result = explainer.explain(
      task: _task(
        const [
          PlanReasonTrace(reason: PlanningReason.mappingStrength, contribution: 0.8),
        ],
        priority: PlanPriority.bonus,
      ),
      competency: _competency,
    );

    expect(result.code, PlanReasonCode.learnerChoice);
  });
}
