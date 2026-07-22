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
    expect(recommendation.reason, contains('practice'));
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

  test('excludes the completed mission when choosing the next mission', () {
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
      excludedMissionIds: {'cafe'},
    );

    expect(recommendation.mission.id, 'market');
  });

  // Every fixture below has its own 'calib' calibration mission — its
  // primaryCompetencyId needs evidence too, or the selector (correctly)
  // keeps recommending calibration itself, same as the shared _catalog
  // tests above already account for.
  final _calibDone = _state(
    competencyId: 'calib',
    masteryEstimate: 0.7,
    confidence: 0.7,
    evidenceCount: 5,
  );

  test('excludes a scenario two bands below the learner (the original bug)', () {
    // This is the exact shape of the reported bug: an A2 scenario (e.g.
    // "order coffee") staying eligible for a B2 learner forever because the
    // level filter only ever checked a ceiling, never a floor.
    final recommendation = selector.select(
      catalog: _levelWindowCatalog,
      level: 'b2',
      goal: 'everyday',
      competencyStates: [_calibDone],
    );

    expect(recommendation.mission.id, 'b2_match');
  });

  test('a lower-level scenario is reachable only as a fallback', () {
    final recommendation = selector.select(
      catalog: _a2OnlyCatalog,
      level: 'b1',
      goal: 'everyday',
      competencyStates: [_calibDone],
    );

    // Nothing within one band of B1 exists in this catalog, so the A2
    // mission is reachable as a last-resort fallback, not silently dropped.
    expect(recommendation.mission.id, 'a2_only');
  });

  test('a mastered competency is excluded outright, not just deranked', () {
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
        _state(
          competencyId: 'cafe',
          masteryEstimate: 0.95,
          confidence: 0.9,
          evidenceCount: 10,
        ),
      ],
    );

    expect(recommendation.mission.id, 'market');
  });

  test('difficulty boost reaches a higher band than the base level would', () {
    // b2_boosted is two bands above the base 'a2' level — out of reach
    // without the boost — and carries a due-for-review state so that once
    // the boost DOES make it eligible, it isn't left to an arbitrary
    // alphabetical tie-break against a2_base to decide the winner.
    final dueForBoosted = CompetencyState(
      competencyId: 'b2_skill',
      modality: PerformanceModality.controlledSpeaking,
      masteryEstimate: 0.4,
      confidence: 0.5,
      retentionStrength: 0.5,
      evidenceCount: 4,
      transferStatus: TransferStatus.singleModality,
      learnerModelType: 'test',
      modelVersion: 'test',
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    final states = [_calibDone, dueForBoosted];

    final withoutBoost = selector.select(
      catalog: _boostCatalog,
      level: 'a2',
      goal: 'everyday',
      competencyStates: states,
    );
    expect(withoutBoost.mission.id, 'a2_base');

    final withBoost = selector.select(
      catalog: _boostCatalog,
      level: 'a2',
      goal: 'everyday',
      competencyStates: states,
      difficultyBoost: true,
    );
    expect(withBoost.mission.id, 'b2_boosted');
  });
}

final _levelWindowCatalog = MissionCatalog(
  missions: [
    MissionDefinition(
      id: 'calib',
      title: 'calib',
      scenario: 'calib',
      levelBand: 'A1',
      primaryCompetencyId: 'calib',
      promptContext: 'context',
      calibration: true,
      steps: const [],
    ),
    MissionDefinition(
      id: 'a2_low',
      title: 'a2_low',
      scenario: 'a2_low',
      levelBand: 'A2',
      primaryCompetencyId: 'a2_skill',
      promptContext: 'context',
      steps: const [],
    ),
    MissionDefinition(
      id: 'b2_match',
      title: 'b2_match',
      scenario: 'b2_match',
      levelBand: 'B2',
      primaryCompetencyId: 'b2_skill',
      promptContext: 'context',
      steps: const [],
    ),
  ],
);

final _a2OnlyCatalog = MissionCatalog(
  missions: [
    MissionDefinition(
      id: 'calib',
      title: 'calib',
      scenario: 'calib',
      levelBand: 'A1',
      primaryCompetencyId: 'calib',
      promptContext: 'context',
      calibration: true,
      steps: const [],
    ),
    MissionDefinition(
      id: 'a2_only',
      title: 'a2_only',
      scenario: 'a2_only',
      levelBand: 'A2',
      primaryCompetencyId: 'a2_skill',
      promptContext: 'context',
      steps: const [],
    ),
  ],
);

final _boostCatalog = MissionCatalog(
  missions: [
    MissionDefinition(
      id: 'calib',
      title: 'calib',
      scenario: 'calib',
      levelBand: 'A1',
      primaryCompetencyId: 'calib',
      promptContext: 'context',
      calibration: true,
      steps: const [],
    ),
    MissionDefinition(
      id: 'a2_base',
      title: 'a2_base',
      scenario: 'a2_base',
      levelBand: 'A2',
      primaryCompetencyId: 'a2_skill',
      promptContext: 'context',
      steps: const [],
    ),
    MissionDefinition(
      id: 'b2_boosted',
      title: 'b2_boosted',
      scenario: 'b2_boosted',
      levelBand: 'B2',
      primaryCompetencyId: 'b2_skill',
      promptContext: 'context',
      steps: const [],
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
      id: 'market',
      title: 'Shop at a market',
      scenario: 'Market',
      levelBand: 'A2',
      primaryCompetencyId: 'market',
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
