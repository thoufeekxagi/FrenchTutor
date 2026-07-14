class SRSState {
  SRSState({
    required this.entryId,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.reps = 0,
    this.dueAt,
    this.lastGrade,
    this.introducedOn,
    this.lastReviewedAt,
  });

  final String entryId;
  double ease;
  double intervalDays;
  int reps;
  DateTime? dueAt;
  SRSGrade? lastGrade;

  /// Local date (YYYY-MM-DD) this card was first graded — the honest anchor
  /// for the new-cards-per-day budget (fixes the due_at-derived counting bug).
  String? introducedOn;
  DateTime? lastReviewedAt;

  bool get isKnown => reps >= 3 && intervalDays >= 21;
}

enum SRSGrade { again, hard, good, easy }

/// How a grade was arrived at — recorded in the append-only review log so
/// pacing/progress can distinguish real recall from inference.
enum SRSResponseType { unaided, hinted, selfReported, auto }
