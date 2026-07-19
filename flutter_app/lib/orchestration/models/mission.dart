import 'dart:collection';

import 'competency.dart';

class MissionCatalog {
  MissionCatalog({required Iterable<MissionDefinition> missions})
    : missions = UnmodifiableListView(List.of(missions));

  final List<MissionDefinition> missions;

  factory MissionCatalog.fromJson(Map<String, dynamic> json) => MissionCatalog(
    missions: (json['missions'] as List)
        .map(
          (item) =>
              MissionDefinition.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList(growable: false),
  );
}

class MissionDefinition {
  MissionDefinition({
    required this.id,
    required this.title,
    required this.scenario,
    required this.levelBand,
    required this.primaryCompetencyId,
    required this.steps,
    required this.promptContext,
    this.supportingCompetencyIds = const [],
    this.goalIds = const [],
    this.calibration = false,
  });

  final String id;
  final String title;
  final String scenario;
  final String levelBand;
  final String primaryCompetencyId;
  final List<String> supportingCompetencyIds;
  final List<String> goalIds;
  final List<MissionStepDefinition> steps;
  final String promptContext;
  final bool calibration;

  factory MissionDefinition.fromJson(Map<String, dynamic> json) =>
      MissionDefinition(
        id: json['id'] as String,
        title: json['title'] as String,
        scenario: json['scenario'] as String,
        levelBand: json['levelBand'] as String,
        primaryCompetencyId: json['primaryCompetencyId'] as String,
        supportingCompetencyIds: List<String>.from(
          json['supportingCompetencyIds'] as List? ?? const [],
        ),
        goalIds: List<String>.from(json['goalIds'] as List? ?? const []),
        steps: (json['steps'] as List)
            .map(
              (item) => MissionStepDefinition.fromJson(
                (item as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
        promptContext: json['promptContext'] as String,
        calibration: json['calibration'] as bool? ?? false,
      );
}

class MissionStepDefinition {
  MissionStepDefinition({
    required this.id,
    required this.contentItemId,
    required this.modality,
    required this.estimatedMinutes,
    required this.evidenceGoal,
    this.generatedScenario = false,
  });

  final String id;
  final String contentItemId;
  final PerformanceModality modality;
  final int estimatedMinutes;
  final String evidenceGoal;
  final bool generatedScenario;

  factory MissionStepDefinition.fromJson(Map<String, dynamic> json) =>
      MissionStepDefinition(
        id: json['id'] as String,
        contentItemId: json['contentItemId'] as String,
        modality: PerformanceModality.fromWireName(json['modality'] as String),
        estimatedMinutes: json['estimatedMinutes'] as int,
        evidenceGoal: json['evidenceGoal'] as String,
        generatedScenario: json['generatedScenario'] as bool? ?? false,
      );
}
