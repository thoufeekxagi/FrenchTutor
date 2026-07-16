import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/planning/orchestrator.dart';

void main() {
  group('O4 baseline planner', () {
    test('commuter plan respects speaking, network, and time constraints', () {
      final plan = const Orchestrator().plan(
        framework: _framework,
        context: const PlanningContext(
          availableMinutes: 20,
          canSpeakAloud: false,
          networkAvailable: false,
          goal: 'conversation',
          competencyStates: [
            PlannerCompetencyState(
              competencyId: 'foundation',
              belief: 0.8,
              dueForReview: true,
            ),
            PlannerCompetencyState(
              competencyId: 'conversation',
              belief: 0.4,
              uncertainty: 0.6,
              recentErrors: 1,
            ),
          ],
        ),
      );

      expect(plan.totalMinutes, lessThanOrEqualTo(20));
      expect(plan.tasks, isNotEmpty);
      expect(plan.tasks.any((task) => task.isSpeaking), isFalse);
      expect(plan.tasks.any((task) => task.requiresNetwork), isFalse);
    });

    test(
      'intensive context includes more modalities and remains deterministic',
      () {
        const context = PlanningContext(
          availableMinutes: 60,
          canSpeakAloud: true,
          networkAvailable: true,
          goal: 'conversation',
          competencyStates: [
            PlannerCompetencyState(
              competencyId: 'foundation',
              belief: 0.9,
              dueForReview: true,
            ),
            PlannerCompetencyState(
              competencyId: 'conversation',
              belief: 0.45,
              uncertainty: 0.7,
              recentErrors: 2,
            ),
            PlannerCompetencyState(
              competencyId: 'transfer',
              belief: 0.7,
              uncertainty: 0.2,
            ),
          ],
        );
        const orchestrator = Orchestrator();

        final first = orchestrator.plan(
          framework: _framework,
          context: context,
        );
        final second = orchestrator.plan(
          framework: _framework,
          context: context,
        );

        expect(first.tasks.length, greaterThan(2));
        expect(first.tasks.any((task) => task.isSpeaking), isTrue);
        expect(
          first.tasks.map((task) => task.contentItemId),
          second.tasks.map((task) => task.contentItemId),
        );
        expect(
          first.tasks.map((task) => task.score),
          second.tasks.map((task) => task.score),
        );
      },
    );

    test(
      'weak skill with errors is a Must and carries a complete reason trace',
      () {
        final plan = const Orchestrator().plan(
          framework: _framework,
          context: const PlanningContext(
            availableMinutes: 20,
            canSpeakAloud: true,
            networkAvailable: true,
            goal: '',
            competencyStates: [
              PlannerCompetencyState(competencyId: 'foundation', belief: 0.85),
              PlannerCompetencyState(
                competencyId: 'conversation',
                belief: 0.2,
                uncertainty: 0.8,
                recentErrors: 3,
              ),
            ],
          ),
        );

        final first = plan.tasks.first;
        expect(first.competencyId, 'conversation');
        expect(first.priority, PlanPriority.must);
        expect(
          first.reasonTrace.map((item) => item.reason).toSet(),
          containsAll(PlanningReason.values),
        );
        expect(
          first.reasonTrace
              .firstWhere((item) => item.reason == PlanningReason.recentError)
              .contribution,
          greaterThan(0),
        );
      },
    );

    test('blocks unmet prerequisites and unlocks them when ready', () {
      const blockedContext = PlanningContext(
        availableMinutes: 60,
        canSpeakAloud: true,
        networkAvailable: true,
        goal: 'transfer',
        competencyStates: [
          PlannerCompetencyState(competencyId: 'foundation', belief: 0.9),
          PlannerCompetencyState(competencyId: 'conversation', belief: 0.5),
        ],
      );
      const readyContext = PlanningContext(
        availableMinutes: 60,
        canSpeakAloud: true,
        networkAvailable: true,
        goal: 'transfer',
        competencyStates: [
          PlannerCompetencyState(competencyId: 'foundation', belief: 0.9),
          PlannerCompetencyState(competencyId: 'conversation', belief: 0.9),
        ],
      );

      final blocked = const Orchestrator().plan(
        framework: _framework,
        context: blockedContext,
      );
      final ready = const Orchestrator().plan(
        framework: _framework,
        context: readyContext,
      );

      expect(
        blocked.tasks.any((task) => task.competencyId == 'transfer'),
        isFalse,
      );
      expect(
        ready.tasks.any((task) => task.competencyId == 'transfer'),
        isTrue,
      );
    });

    test('tight budget selects only tasks that fit', () {
      final plan = const Orchestrator().plan(
        framework: _framework,
        context: const PlanningContext(
          availableMinutes: 8,
          canSpeakAloud: true,
          networkAvailable: true,
          goal: '',
          competencyStates: [
            PlannerCompetencyState(
              competencyId: 'foundation',
              belief: 0.4,
              dueForReview: true,
            ),
          ],
        ),
      );

      expect(plan.totalMinutes, lessThanOrEqualTo(8));
      expect(plan.tasks, hasLength(1));
      expect(plan.tasks.single.estimatedMinutes, 7);
      expect(plan.remainingMinutes, 1);
    });
  });
}

const _version = 'planner_test_v1';

const _framework = CompetencyFramework(
  frameworkVersion: '1.0.0',
  curriculumVersion: _version,
  competencies: [
    Competency(
      id: 'foundation',
      kind: CompetencyKind.lexical,
      title: 'Foundation vocabulary',
      description: 'Core words',
      difficultyBand: 'A1',
      prerequisiteIds: [],
      curriculumVersion: _version,
    ),
    Competency(
      id: 'conversation',
      kind: CompetencyKind.function,
      title: 'Conversation',
      description: 'Everyday conversation',
      difficultyBand: 'A2',
      prerequisiteIds: ['foundation'],
      curriculumVersion: _version,
    ),
    Competency(
      id: 'transfer',
      kind: CompetencyKind.discourse,
      title: 'Transfer',
      description: 'Apply conversation in a new situation',
      difficultyBand: 'B1',
      prerequisiteIds: ['conversation'],
      curriculumVersion: _version,
    ),
  ],
  mappings: [
    ContentCompetencyMapping(
      id: 'foundation_read',
      contentItemId: 'foundation_read',
      competencyId: 'foundation',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.readingRecognition,
      weight: 0.8,
      curriculumVersion: _version,
    ),
    ContentCompetencyMapping(
      id: 'foundation_listen',
      contentItemId: 'foundation_listen',
      competencyId: 'foundation',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.listeningRecognition,
      weight: 0.9,
      curriculumVersion: _version,
    ),
    ContentCompetencyMapping(
      id: 'conversation_write',
      contentItemId: 'conversation_write',
      competencyId: 'conversation',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.controlledWriting,
      weight: 0.7,
      curriculumVersion: _version,
    ),
    ContentCompetencyMapping(
      id: 'conversation_speak',
      contentItemId: 'conversation_speak',
      competencyId: 'conversation',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.controlledSpeaking,
      weight: 0.8,
      curriculumVersion: _version,
    ),
    ContentCompetencyMapping(
      id: 'conversation_live',
      contentItemId: 'conversation_live',
      competencyId: 'conversation',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.spontaneousSpeaking,
      weight: 1,
      curriculumVersion: _version,
    ),
    ContentCompetencyMapping(
      id: 'transfer_write',
      contentItemId: 'transfer_write',
      competencyId: 'transfer',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.spontaneousWriting,
      weight: 1,
      curriculumVersion: _version,
    ),
  ],
);
