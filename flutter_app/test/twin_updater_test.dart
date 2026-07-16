import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/twin/twin_updater.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1);

  LearnerObservation observation({
    String competencyId = 'grammar.past',
    PerformanceModality modality = PerformanceModality.controlledWriting,
    double correctness = 1,
    EvidenceSupportLevel support = EvidenceSupportLevel.unaidedProduction,
    double reliability = 1,
    double evaluatorConfidence = 1,
    bool genuineLearningOpportunity = true,
    Duration elapsed = Duration.zero,
    DateTime? observedAt,
  }) => LearnerObservation(
    competencyId: competencyId,
    modality: modality,
    correctness: correctness,
    support: support,
    reliability: reliability,
    evaluatorConfidence: evaluatorConfidence,
    genuineLearningOpportunity: genuineLearningOpportunity,
    elapsed: elapsed,
    observedAt: observedAt ?? start,
  );

  test('same inputs produce the same posterior', () {
    final input = observation(correctness: 0.8, reliability: 0.75);
    final first = O3ProbabilisticLearnerModel().observe(input);
    final second = O3ProbabilisticLearnerModel().observe(input);

    expect(first.pKnown, second.pKnown);
    expect(first.confidence, second.confidence);
    expect(first.evidenceCount, second.evidenceCount);
  });

  test('positive unaided evidence raises belief more than hinted evidence', () {
    final unaided = O3ProbabilisticLearnerModel().observe(observation());
    final hinted = O3ProbabilisticLearnerModel().observe(
      observation(support: EvidenceSupportLevel.hintedProduction),
    );

    expect(unaided.pKnown, greaterThan(hinted.pKnown));
    expect(unaided.confidence, greaterThan(hinted.confidence));
  });

  test('weak low-confidence evaluator evidence cannot establish mastery', () {
    final model = O3ProbabilisticLearnerModel();
    for (var index = 0; index < 20; index++) {
      model.observe(
        observation(
          evaluatorConfidence: 0.05,
          reliability: 0.2,
          observedAt: start.add(Duration(minutes: index)),
        ),
      );
    }

    final belief = model.beliefFor(
      'grammar.past',
      PerformanceModality.controlledWriting,
    );
    expect(model.isMastered(belief), isFalse);
    expect(belief.confidence, lessThan(model.parameters.masteryConfidence));
  });

  test('elapsed time forgetting lowers the prior', () {
    final model = O3ProbabilisticLearnerModel();
    final learned = model.observe(observation());
    final forgotten = model.observe(
      observation(
        correctness: 0.5,
        reliability: 0,
        evaluatorConfidence: 0,
        genuineLearningOpportunity: false,
        elapsed: const Duration(days: 45),
        observedAt: start.add(const Duration(days: 45)),
      ),
    );

    expect(forgotten.pKnown, lessThan(learned.pKnown));
    expect(forgotten.confidence, lessThan(learned.confidence));
  });

  test('beliefs remain separated by modality', () {
    final model = O3ProbabilisticLearnerModel();
    final writing = model.observe(observation());
    final listening = model.beliefFor(
      'grammar.past',
      PerformanceModality.listeningRecognition,
    );

    expect(writing.pKnown, greaterThan(model.parameters.initialKnown));
    expect(listening.pKnown, model.parameters.initialKnown);
    expect(listening.evidenceCount, 0);
    expect(model.beliefs, hasLength(1));
  });

  test('rebuild is stable for the same unordered observations', () {
    final inputs = [
      observation(
        correctness: 0,
        observedAt: start.add(const Duration(minutes: 2)),
        elapsed: const Duration(minutes: 1),
      ),
      observation(observedAt: start),
      observation(
        correctness: 0.7,
        observedAt: start.add(const Duration(minutes: 1)),
        elapsed: const Duration(minutes: 1),
      ),
    ];
    final first = O3ProbabilisticLearnerModel().rebuild(inputs);
    final second = O3ProbabilisticLearnerModel().rebuild(inputs.reversed);
    final key = const BeliefKey(
      'grammar.past',
      PerformanceModality.controlledWriting,
    );

    expect(first[key]!.pKnown, second[key]!.pKnown);
    expect(first[key]!.confidence, second[key]!.confidence);
    expect(first[key]!.evidenceCount, 3);
    expect(first[key]!.firstObservedAt, start);
    expect(first[key]!.lastObservedAt, start.add(const Duration(minutes: 2)));
  });
}
