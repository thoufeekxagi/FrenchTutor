import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/twin/retention_policy.dart';
import 'package:french_tutor/orchestration/twin/twin_updater.dart';

void main() {
  const policy = RetentionPolicy();

  CompetencyBeliefState belief({
    double pKnown = 0.8,
    double confidence = 0.6,
    int evidenceCount = 3,
    DateTime? lastObservedAt,
  }) => CompetencyBeliefState(
    competencyId: 'competency',
    modality: PerformanceModality.readingRecognition,
    pKnown: pKnown,
    confidence: confidence,
    evidenceCount: evidenceCount,
    firstObservedAt: lastObservedAt,
    lastObservedAt: lastObservedAt,
    modelVersion: 'test',
  );

  test('has no schedule for a belief with no observations yet', () {
    final state = belief(lastObservedAt: null);
    expect(policy.nextReviewAt(state), isNull);
    expect(policy.reviewUrgency(state, DateTime.utc(2026)), 0);
    expect(policy.isDue(state, DateTime.utc(2026)), isFalse);
  });

  test('retentionStrength is the bounded product of mastery and confidence', () {
    expect(
      policy.retentionStrength(belief(pKnown: 0.5, confidence: 0.4)),
      closeTo(0.2, 1e-9),
    );
    expect(policy.retentionStrength(belief(pKnown: 1, confidence: 1)), 1);
  });

  test('is not due before the scheduled review time', () {
    final now = DateTime.utc(2026, 3, 1);
    final state = belief(lastObservedAt: now);
    final next = policy.nextReviewAt(state)!;
    expect(next.isAfter(now), isTrue);
    expect(policy.isDue(state, now), isFalse);
    expect(policy.reviewUrgency(state, now), 0);
  });

  test('urgency saturates to 1 once far enough overdue', () {
    final observedAt = DateTime.utc(2026, 1, 1);
    final state = belief(lastObservedAt: observedAt, pKnown: 0.3, confidence: 0.3);
    final farFuture = observedAt.add(const Duration(days: 400));

    expect(policy.isDue(state, farFuture), isTrue);
    expect(policy.reviewUrgency(state, farFuture), 1);
  });

  test('higher mastery and confidence produce a longer review interval', () {
    final observedAt = DateTime.utc(2026, 1, 1);
    final weak = policy.nextReviewAt(
      belief(pKnown: 0.2, confidence: 0.2, lastObservedAt: observedAt),
    )!;
    final strong = policy.nextReviewAt(
      belief(pKnown: 0.95, confidence: 0.9, lastObservedAt: observedAt),
    )!;
    expect(strong.isAfter(weak), isTrue);
  });
}
