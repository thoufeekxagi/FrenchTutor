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
    Set<String> excludedMissionIds = const {},
    bool difficultyBoost = false,
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
        'A little more practice will help choose your next French mission well.'
      );
    }

    // A learner who's been practicing a lot in one sitting gets nudged up a
    // notch for the rest of that sitting — same idea as the ceiling below,
    // just shifted, so "practiced a lot today" actually raises what's next.
    final effectiveLevel = difficultyBoost
        ? _levelIndex(level) + 1
        : _levelIndex(level);

    final pool = catalog.missions
        .where((mission) => !mission.calibration)
        .where((mission) => !excludedMissionIds.contains(mission.id))
        .where((mission) => _matchesGoal(mission, goal))
        .where(
          (mission) =>
              !_isMastered(mission, statesByCompetency),
        );

    // Strict window first: a scenario more than one band below or above the
    // learner's level is excluded outright — this is the level FLOOR that
    // was missing, without it a lower-level scenario like an A2 café order
    // stayed eligible for B1/B2 learners forever. Only if nothing in that
    // window is available (e.g. right at the very top of the scale with an
    // otherwise-empty pool) does an easy warm-up outside the window become
    // reachable as a fallback, never as the default outcome.
    var candidates = pool
        .where(
          (mission) => _withinWindow(mission.levelBand, effectiveLevel),
        )
        .toList();
    if (candidates.isEmpty) {
      candidates = pool
          .where((mission) => _matchesLevel(mission.levelBand, effectiveLevel))
          .toList();
    }
    if (candidates.isEmpty) {
      return _recommend(
        calibrationMission,
        'This practice helps shape your next mission.'
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

  /// The wide, ceiling-only range kept as a last-resort fallback (see
  /// [select]) for when the strict window below has nothing eligible.
  bool _matchesLevel(String missionLevel, int learnerIndex) {
    final missionIndex = _levelIndex(missionLevel);
    return missionIndex <= learnerIndex + 1;
  }

  /// The real default: a scenario must be within one band of the learner's
  /// level in EITHER direction — this is what stops lower-level content
  /// (e.g. an A2 café order) from staying eligible forever for a B1/B2
  /// learner just because nothing ever excluded it on the low side.
  bool _withinWindow(String missionLevel, int learnerIndex) {
    final missionIndex = _levelIndex(missionLevel);
    return (missionIndex - learnerIndex).abs() <= 1;
  }

  int _levelIndex(String value) => switch (value.toLowerCase()) {
    'a1' || 'zero' || 'basics' => 0,
    'a2' => 1,
    'b1' || 'conversational' => 2,
    'b2' => 3,
    _ => 0,
  };

  /// A competency is solidly mastered — high confidence, high mastery, not
  /// currently due for review — once evidence clearly supports it. Unlike
  /// [_stateScore] (which only deranks a mastered mission), this REMOVES it
  /// from the eligible pool outright; with only a handful of missions per
  /// competency, deranking alone still let a mastered scenario win by
  /// default when nothing else scored higher.
  static const _masteryThreshold = 0.85;
  static const _confidenceThreshold = 0.7;

  bool _isMastered(
    MissionDefinition mission,
    Map<String, List<CompetencyState>> statesByCompetency,
  ) {
    final states = statesByCompetency[mission.primaryCompetencyId] ?? const [];
    if (states.isEmpty) return false;
    return states.every(
      (state) =>
          !state.dueForReview(DateTime.now()) &&
          state.masteryEstimate >= _masteryThreshold &&
          state.confidence >= _confidenceThreshold,
    );
  }

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
      return 'A little more practice will help show how confidently you can do this.';
    }
    return 'This helps you apply a skill you are building in a real conversation.';
  }
}
