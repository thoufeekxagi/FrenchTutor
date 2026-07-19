import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/competency_state.dart';
import 'package:french_tutor/orchestration/models/mission.dart';
import 'package:french_tutor/orchestration/planning/mission_selector.dart';

void main() {
  const selector = MissionSelector();

  test('starts a new learner with the calibration mission', () {
    final recommendation = selector.select(
      catalog: _catalog,
      level: 'a1',
      goal: 'everyday',
      competencyStates: const [],
    );

    expect(recommendation.mission.id, 'calibration');
    expect(recommendation.estimatedMinutes, 10);
    expect(recommendation.reason, contains('evidence'));
  });

  test('selects a matching mission after calibration evidence exists', () {
    final recommendation = selector.select(
      catalog: _catalog,
      level: 'a2',
      goal: 'everyday',
      competencyStates: [
        _state(
          competencyId: 'identity',
          masteryEstimate: 0.65,
          confidence: 0.65,
          evidenceCount: 4,
        ),
      ],
    );

    expect(recommendation.mission.id, 'cafe');
    expect(recommendation.reason, contains('apply'));
  });

  test('does not recommend content beyond the learner level band', () {
    final recommendation = selector.select(
      catalog: _catalog,
      level: 'a1',
      goal: 'everyday',
      competencyStates: [
        _state(
          competencyId: 'identity',
          masteryEstimate: 0.65,
          confidence: 0.65,
          evidenceCount: 4,
        ),
      ],
    );

    expect(recommendation.mission.id, 'cafe');
  });
}

final _catalog = MissionCatalog(
  missions: [
    MissionDefinition(
      id: 'calibration',
      title: 'Introduce yourself',
      scenario: 'First meeting',
      levelBand: 'A1',
      primaryCompetencyId: 'identity',
      calibration: true,
      promptContext: 'context',
      steps: [
        MissionStepDefinition(
          id: 'recognise',
          contentItemId: 'vocab',
          modality: PerformanceModality.readingRecognition,
          estimatedMinutes: 4,
          evidenceGoal: 'recognise',
        ),
        MissionStepDefinition(
          id: 'speak',
          contentItemId: 'speak',
          modality: PerformanceModality.controlledSpeaking,
          estimatedMinutes: 6,
          evidenceGoal: 'speak',
        ),
      ],
    ),
    MissionDefinition(
      id: 'cafe',
      title: 'Order at a café',
      scenario: 'Café',
      levelBand: 'A2',
      primaryCompetencyId: 'cafe',
      goalIds: ['everyday'],
      promptContext: 'context',
      steps: [],
    ),
    MissionDefinition(
      id: 'opinion',
      title: 'Defend an opinion',
      scenario: 'Opinion',
      levelBand: 'B2',
      primaryCompetencyId: 'opinion',
      goalIds: ['everyday'],
      promptContext: 'context',
      steps: [],
    ),
  ],
);

CompetencyState _state({
  required String competencyId,
  required double masteryEstimate,
  required double confidence,
  required int evidenceCount,
}) => CompetencyState(
  competencyId: competencyId,
  modality: PerformanceModality.controlledSpeaking,
  masteryEstimate: masteryEstimate,
  confidence: confidence,
  retentionStrength: 0.5,
  evidenceCount: evidenceCount,
  transferStatus: TransferStatus.singleModality,
  learnerModelType: 'test',
  modelVersion: 'test',
);
