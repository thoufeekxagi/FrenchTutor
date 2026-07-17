import 'twin_updater.dart';

/// Deterministic forgetting/retention schedule (plan section 7.1 step 5, 8
/// and section 5.5 `next_review_at`). Purely a function of a belief state
/// and the current time — same inputs always produce the same schedule.
class RetentionPolicy {
  const RetentionPolicy({
    this.baseIntervalDays = 2,
    this.minIntervalDays = 1,
    this.maxIntervalDays = 60,
    this.urgencySaturationDays = 7,
  }) : assert(baseIntervalDays > 0),
       assert(minIntervalDays > 0),
       assert(maxIntervalDays >= minIntervalDays),
       assert(urgencySaturationDays > 0);

  final double baseIntervalDays;
  final double minIntervalDays;
  final double maxIntervalDays;
  final double urgencySaturationDays;

  /// Combines mastery and confidence into one bounded retention signal.
  /// Neither alone is retention: a high estimate built on one weak event is
  /// not durable, and a confident but low estimate is durably not-known-yet.
  double retentionStrength(CompetencyBeliefState belief) =>
      (belief.pKnown * belief.confidence).clamp(0, 1).toDouble();

  /// Null until there is at least one observation — an item with no
  /// evidence is `insufficient_evidence`, not "due", per plan section 7.2.
  DateTime? nextReviewAt(CompetencyBeliefState belief) {
    final last = belief.lastObservedAt;
    if (last == null) return null;
    final strength = retentionStrength(belief);
    final spacing =
        baseIntervalDays *
        (1 + belief.evidenceCount * 0.4) *
        (0.25 + strength);
    final intervalDays = spacing.clamp(minIntervalDays, maxIntervalDays);
    return last.add(Duration(minutes: (intervalDays * 24 * 60).round()));
  }

  /// 0 when not yet due, saturating to 1 after [urgencySaturationDays]
  /// overdue. Feeds the planner's `reviewUrgency` score component.
  double reviewUrgency(CompetencyBeliefState belief, DateTime now) {
    final next = nextReviewAt(belief);
    if (next == null || !now.isAfter(next)) return 0;
    final overdueDays = now.difference(next).inMinutes / (24 * 60);
    return (overdueDays / urgencySaturationDays).clamp(0, 1).toDouble();
  }

  bool isDue(CompetencyBeliefState belief, DateTime now) {
    final next = nextReviewAt(belief);
    return next != null && !next.isAfter(now);
  }
}
