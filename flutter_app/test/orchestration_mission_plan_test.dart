import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/plan_store.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/models/mission.dart';
import 'package:french_tutor/orchestration/runtime/orchestration_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('persists an immutable selected mission in today’s plan', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final plan = const OrchestrationService().ensureTodayPlan(
      framework: _framework,
      competencyStates: const [],
      errors: const [],
      planStore: PlanStore(db),
      localDate: '2026-07-19',
      availableMinutes: 20,
      canSpeakAloud: true,
      networkAvailable: true,
      goal: 'everyday',
      learnerLevel: 'a1',
      missionCatalog: _catalog,
    );

    expect(plan.inputSnapshot['missionId'], 'calibration');
    expect(plan.inputSnapshot['missionTitle'], 'Introduce yourself');
    expect(plan.tasks.map((task) => task.contentItemId), ['read', 'speak']);
    expect(
      plan.explanation,
      'A little more practice will help choose your next French mission well.',
    );
  });
}

const _framework = CompetencyFramework(
  frameworkVersion: 'test',
  curriculumVersion: 'test',
  competencies: [
    Competency(
      id: 'identity',
      kind: CompetencyKind.function,
      title: 'Identity',
      description: 'Identity',
      difficultyBand: 'A1',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
  ],
  mappings: [
    ContentCompetencyMapping(
      id: 'read',
      contentItemId: 'read',
      competencyId: 'identity',
      role: ContentMappingRole.teaches,
      modality: PerformanceModality.readingRecognition,
      weight: 0.8,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'speak',
      contentItemId: 'speak',
      competencyId: 'identity',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.controlledSpeaking,
      weight: 0.9,
      curriculumVersion: 'test',
    ),
  ],
);

final _catalog = MissionCatalog(
  missions: [
    MissionDefinition(
      id: 'calibration',
      title: 'Introduce yourself',
      scenario: 'First meeting',
      levelBand: 'A1',
      primaryCompetencyId: 'identity',
      goalIds: const ['everyday'],
      calibration: true,
      promptContext: 'context',
      steps: [
        MissionStepDefinition(
          id: 'read',
          contentItemId: 'read',
          modality: PerformanceModality.readingRecognition,
          estimatedMinutes: 4,
          evidenceGoal: 'recognition',
        ),
        MissionStepDefinition(
          id: 'speak',
          contentItemId: 'speak',
          modality: PerformanceModality.controlledSpeaking,
          estimatedMinutes: 6,
          evidenceGoal: 'production',
        ),
      ],
    ),
  ],
);
