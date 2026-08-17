import 'content_models.dart';

/// A self-contained exam-readiness attempt. Exam attempts deliberately do not
/// use the regular reading/listening library records: they belong to the
/// selected exam, level, and skill and can be reviewed from the readiness area
/// without changing the learner's course library.
class ExamPracticeAttempt {
  const ExamPracticeAttempt({
    required this.id,
    required this.examName,
    required this.levelBand,
    required this.skill,
    required this.story,
    required this.createdAt,
    this.completedAt,
    this.score,
    this.total,
  });

  final String id;
  final String examName;
  final String levelBand;
  final String skill;
  final GeneratedStory story;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int? score;
  final int? total;

  bool get isCompleted => completedAt != null;
}

class ExamPracticeSummary {
  const ExamPracticeSummary({
    required this.id,
    required this.examName,
    required this.levelBand,
    required this.skill,
    required this.createdAt,
    this.completedAt,
    this.score,
    this.total,
  });

  final String id;
  final String examName;
  final String levelBand;
  final String skill;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int? score;
  final int? total;

  bool get isCompleted => completedAt != null;
}
