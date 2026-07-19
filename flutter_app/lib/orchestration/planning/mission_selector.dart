import '../models/competency_state.dart';
import '../models/mission.dart';

class MissionRecommendation {
  const MissionRecommendation({
    required this.mission,
    required this.reason,
    required this.estimatedMinutes,
  });

  final MissionDefinition mission;
  final String reason;
  final int estimatedMinutes;
}

class MissionSelector {
  const MissionSelector();

  MissionRecommendation select({
    required MissionCatalog catalog,
    required String level,
    required String goal,
    required Iterable<CompetencyState> competencyStates,
  }) {
    final statesByCompetency = <String, List<CompetencyState>>{};
    for (final state in competencyStates) {
      statesByCompetency.putIfAbsent(state.competencyId, () => []).add(state);
    }
    final calibration = catalog.missions.where(
      (mission) => mission.calibration,
    );
    final calibrationMission = calibration.firstWhere(
      (mission) => _needsCalibration(mission, statesByCompetency),
      orElse: () => catalog.missions.first,
    );
    if (_needsCalibration(calibrationMission, statesByCompetency)) {
      return _recommend(
        calibrationMission,
        'We need a little evidence to choose your next French practice well.',
      );
    }

    final candidates = catalog.missions
        .where((mission) => !mission.calibration)
        .where((mission) => _matchesGoal(mission, goal))
        .where((mission) => _matchesLevel(mission.levelBand, level))
        .toList();
    if (candidates.isEmpty) {
      return _recommend(
        calibrationMission,
        'This gives us the evidence needed to shape your next mission.',
      );
    }

    candidates.sort((a, b) {
      final aState = _stateScore(a, statesByCompetency);
      final bState = _stateScore(b, statesByCompetency);
      final byState = bState.compareTo(aState);
      return byState != 0 ? byState : a.id.compareTo(b.id);
    });
    final mission = candidates.first;
    return _recommend(mission, _reasonFor(mission, statesByCompetency));
  }

  MissionRecommendation _recommend(MissionDefinition mission, String reason) =>
      MissionRecommendation(
        mission: mission,
        reason: reason,
        estimatedMinutes: mission.steps.fold(
          0,
          (total, step) => total + step.estimatedMinutes,
        ),
      );

  bool _needsCalibration(
    MissionDefinition mission,
    Map<String, List<CompetencyState>> statesByCompetency,
  ) {
    final states = statesByCompetency[mission.primaryCompetencyId] ?? const [];
    return states.isEmpty || states.every((state) => state.needsMoreEvidence);
  }

  bool _matchesGoal(MissionDefinition mission, String goal) =>
      mission.goalIds.isEmpty || mission.goalIds.contains(goal);

  bool _matchesLevel(String missionLevel, String learnerLevel) {
    final missionIndex = _levelIndex(missionLevel);
    final learnerIndex = _levelIndex(learnerLevel);
    return missionIndex <= learnerIndex + 1;
  }

  int _levelIndex(String value) => switch (value.toLowerCase()) {
    'a1' || 'zero' || 'basics' => 0,
    'a2' => 1,
    'b1' || 'conversational' => 2,
    'b2' => 3,
    _ => 0,
  };

  double _stateScore(
    MissionDefinition mission,
    Map<String, List<CompetencyState>> statesByCompetency,
  ) {
    final states = statesByCompetency[mission.primaryCompetencyId] ?? const [];
    if (states.isEmpty) return 1;
    return states.fold<double>(0, (score, state) {
      final due = state.dueForReview(DateTime.now()) ? 2 : 0;
      final uncertainty = 1 - state.confidence;
      final need = 1 - state.masteryEstimate;
      return score + due + uncertainty + need;
    });
  }

  String _reasonFor(
    MissionDefinition mission,
    Map<String, List<CompetencyState>> statesByCompetency,
  ) {
    final states = statesByCompetency[mission.primaryCompetencyId] ?? const [];
    if (states.any((state) => state.dueForReview(DateTime.now()))) {
      return '${mission.title} is due for review.';
    }
    if (states.any((state) => state.needsMoreEvidence)) {
      return 'More evidence is needed to know how confidently you can do this.';
    }
    return 'This helps you apply a skill you are building in a real conversation.';
  }
}
