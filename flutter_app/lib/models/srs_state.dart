class SRSState {
  SRSState({
    required this.entryId,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.reps = 0,
    this.dueAt,
    this.lastGrade,
  });

  final String entryId;
  double ease;
  double intervalDays;
  int reps;
  DateTime? dueAt;
  int? lastGrade;

  bool get isKnown => reps >= 3 && intervalDays >= 21;
}

enum SRSGrade { again, good, easy }
