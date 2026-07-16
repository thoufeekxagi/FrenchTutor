import 'dart:math' as math;

import '../models/competency.dart';

class BktParameters {
  const BktParameters({
    this.initialKnown = 0.18,
    this.initialConfidence = 0.05,
    this.learnRate = 0.12,
    this.guessRate = 0.22,
    this.slipRate = 0.10,
    this.dailyForgetRate = 0.015,
    this.confidenceGrowthRate = 0.30,
    this.dailyConfidenceDecay = 0.01,
    this.minimumProbability = 0.001,
    this.maximumProbability = 0.999,
    this.masteryProbability = 0.90,
    this.masteryConfidence = 0.55,
    this.modelVersion = 'o3-bkt-v1',
  }) : assert(initialKnown >= 0 && initialKnown <= 1),
       assert(initialConfidence >= 0 && initialConfidence <= 1),
       assert(learnRate >= 0 && learnRate <= 1),
       assert(guessRate > 0 && guessRate < 1),
       assert(slipRate > 0 && slipRate < 1),
       assert(dailyForgetRate >= 0 && dailyForgetRate < 1),
       assert(confidenceGrowthRate >= 0 && confidenceGrowthRate <= 1),
       assert(dailyConfidenceDecay >= 0 && dailyConfidenceDecay < 1),
       assert(minimumProbability > 0),
       assert(maximumProbability < 1),
       assert(minimumProbability < maximumProbability),
       assert(masteryProbability > minimumProbability),
       assert(masteryProbability < maximumProbability),
       assert(masteryConfidence >= 0 && masteryConfidence <= 1);

  final double initialKnown;
  final double initialConfidence;
  final double learnRate;
  final double guessRate;
  final double slipRate;
  final double dailyForgetRate;
  final double confidenceGrowthRate;
  final double dailyConfidenceDecay;
  final double minimumProbability;
  final double maximumProbability;
  final double masteryProbability;
  final double masteryConfidence;
  final String modelVersion;
}

class LearnerObservation {
  LearnerObservation({
    required this.competencyId,
    required this.modality,
    required this.correctness,
    required this.support,
    required this.reliability,
    required this.evaluatorConfidence,
    required this.genuineLearningOpportunity,
    required this.elapsed,
    required this.observedAt,
  }) {
    if (competencyId.isEmpty) {
      throw ArgumentError.value(
        competencyId,
        'competencyId',
        'must not be empty',
      );
    }
    _requireUnit(correctness, 'correctness');
    _requireUnit(reliability, 'reliability');
    _requireUnit(evaluatorConfidence, 'evaluatorConfidence');
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
  }

  final String competencyId;
  final PerformanceModality modality;
  final double correctness;
  final EvidenceSupportLevel support;
  final double reliability;
  final double evaluatorConfidence;
  final bool genuineLearningOpportunity;
  final Duration elapsed;
  final DateTime observedAt;

  static void _requireUnit(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw RangeError.range(value, 0, 1, name);
    }
  }
}

class BeliefKey {
  const BeliefKey(this.competencyId, this.modality);

  final String competencyId;
  final PerformanceModality modality;

  @override
  bool operator ==(Object other) =>
      other is BeliefKey &&
      competencyId == other.competencyId &&
      modality == other.modality;

  @override
  int get hashCode => Object.hash(competencyId, modality);
}

class CompetencyBeliefState {
  const CompetencyBeliefState({
    required this.competencyId,
    required this.modality,
    required this.pKnown,
    required this.confidence,
    required this.evidenceCount,
    required this.firstObservedAt,
    required this.lastObservedAt,
    required this.modelVersion,
  });

  final String competencyId;
  final PerformanceModality modality;
  final double pKnown;
  final double confidence;
  final int evidenceCount;
  final DateTime? firstObservedAt;
  final DateTime? lastObservedAt;
  final String modelVersion;
}

abstract interface class LearnerStateModel {
  BktParameters get parameters;

  CompetencyBeliefState beliefFor(
    String competencyId,
    PerformanceModality modality,
  );

  CompetencyBeliefState observe(LearnerObservation observation);

  Map<BeliefKey, CompetencyBeliefState> rebuild(
    Iterable<LearnerObservation> observations,
  );

  bool isMastered(CompetencyBeliefState state);
}

class O3ProbabilisticLearnerModel implements LearnerStateModel {
  O3ProbabilisticLearnerModel({this.parameters = const BktParameters()});

  @override
  final BktParameters parameters;
  final Map<BeliefKey, CompetencyBeliefState> _beliefs = {};

  Map<BeliefKey, CompetencyBeliefState> get beliefs =>
      Map.unmodifiable(_beliefs);

  @override
  CompetencyBeliefState beliefFor(
    String competencyId,
    PerformanceModality modality,
  ) =>
      _beliefs[BeliefKey(competencyId, modality)] ??
      CompetencyBeliefState(
        competencyId: competencyId,
        modality: modality,
        pKnown: _bounded(parameters.initialKnown),
        confidence: _unit(parameters.initialConfidence),
        evidenceCount: 0,
        firstObservedAt: null,
        lastObservedAt: null,
        modelVersion: parameters.modelVersion,
      );

  @override
  CompetencyBeliefState observe(LearnerObservation observation) {
    final key = BeliefKey(observation.competencyId, observation.modality);
    final next = update(beliefFor(key.competencyId, key.modality), observation);
    _beliefs[key] = next;
    return next;
  }

  CompetencyBeliefState update(
    CompetencyBeliefState prior,
    LearnerObservation observation,
  ) {
    if (prior.competencyId != observation.competencyId ||
        prior.modality != observation.modality) {
      throw ArgumentError('Prior and observation must address the same belief');
    }

    final days =
        observation.elapsed.inMicroseconds / Duration.microsecondsPerDay;
    final retained = math.pow(1 - parameters.dailyForgetRate, days).toDouble();
    final confidenceRetained = math
        .pow(1 - parameters.dailyConfidenceDecay, days)
        .toDouble();
    final forgotten = _bounded(
      parameters.initialKnown +
          (prior.pKnown - parameters.initialKnown) * retained,
    );
    final decayedConfidence = _unit(prior.confidence * confidenceRetained);
    final strength = _unit(
      observation.reliability *
          observation.evaluatorConfidence *
          _supportWeight(observation.support),
    );
    final knownLikelihood =
        observation.correctness * (1 - parameters.slipRate) +
        (1 - observation.correctness) * parameters.slipRate;
    final unknownLikelihood =
        observation.correctness * parameters.guessRate +
        (1 - observation.correctness) * (1 - parameters.guessRate);
    final priorOdds = forgotten / (1 - forgotten);
    final evidenceRatio = math
        .pow(knownLikelihood / unknownLikelihood, strength)
        .toDouble();
    var posterior = _bounded(
      priorOdds * evidenceRatio / (1 + priorOdds * evidenceRatio),
    );
    if (observation.genuineLearningOpportunity) {
      posterior = _bounded(
        posterior +
            (1 - posterior) *
                parameters.learnRate *
                strength *
                observation.correctness,
      );
    }
    final confidenceGain =
        parameters.confidenceGrowthRate *
        strength *
        (observation.genuineLearningOpportunity ? 1 : 0.5);
    final confidence = _unit(
      decayedConfidence + (1 - decayedConfidence) * confidenceGain,
    );

    return CompetencyBeliefState(
      competencyId: prior.competencyId,
      modality: prior.modality,
      pKnown: posterior,
      confidence: confidence,
      evidenceCount: prior.evidenceCount + 1,
      firstObservedAt: prior.firstObservedAt ?? observation.observedAt,
      lastObservedAt: observation.observedAt,
      modelVersion: parameters.modelVersion,
    );
  }

  @override
  Map<BeliefKey, CompetencyBeliefState> rebuild(
    Iterable<LearnerObservation> observations,
  ) {
    final ordered = observations.toList()..sort(_compareObservations);
    _beliefs.clear();
    for (final observation in ordered) {
      observe(observation);
    }
    return beliefs;
  }

  @override
  bool isMastered(CompetencyBeliefState state) =>
      state.pKnown >= parameters.masteryProbability &&
      state.confidence >= parameters.masteryConfidence;

  double _bounded(double value) =>
      value.clamp(parameters.minimumProbability, parameters.maximumProbability);

  static double _unit(double value) => value.clamp(0.0, 1.0);

  static double _supportWeight(EvidenceSupportLevel support) =>
      switch (support) {
        EvidenceSupportLevel.recognition => 0.55,
        EvidenceSupportLevel.cuedRecall => 0.68,
        EvidenceSupportLevel.hintedProduction => 0.45,
        EvidenceSupportLevel.unaidedProduction => 0.90,
        EvidenceSupportLevel.spontaneousTransfer => 1.0,
      };

  static int _compareObservations(
    LearnerObservation left,
    LearnerObservation right,
  ) {
    var result = left.observedAt.compareTo(right.observedAt);
    if (result != 0) return result;
    result = left.competencyId.compareTo(right.competencyId);
    if (result != 0) return result;
    result = left.modality.index.compareTo(right.modality.index);
    if (result != 0) return result;
    result = left.support.index.compareTo(right.support.index);
    if (result != 0) return result;
    result = left.correctness.compareTo(right.correctness);
    if (result != 0) return result;
    result = left.reliability.compareTo(right.reliability);
    if (result != 0) return result;
    result = left.evaluatorConfidence.compareTo(right.evaluatorConfidence);
    if (result != 0) return result;
    result = left.genuineLearningOpportunity == right.genuineLearningOpportunity
        ? 0
        : left.genuineLearningOpportunity
        ? 1
        : -1;
    if (result != 0) return result;
    return left.elapsed.compareTo(right.elapsed);
  }
}
