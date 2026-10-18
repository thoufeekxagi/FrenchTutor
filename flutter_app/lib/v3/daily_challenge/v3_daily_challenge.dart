import '../lesson/v3_lesson.dart';
export '../lesson/v3_lesson.dart' show V3AnswerFeedback;

/// An immutable daily package. The challenge is content data and always uses
/// the reviewed lesson step renderer; it cannot add behavior to the app.
class V3DailyChallenge {
  const V3DailyChallenge({
    required this.id,
    required this.level,
    required this.primarySkill,
    required this.title,
    required this.summary,
    required this.minutes,
    required this.steps,
    required this.lesson,
    required this.remote,
    this.attemptId,
    this.currentStep = 0,
    this.completed = false,
  });

  final String id;
  final String level;
  final String primarySkill;
  final String title;
  final String summary;
  final int minutes;
  final List<String> steps;
  final V3Lesson lesson;
  final bool remote;
  final String? attemptId;
  final int currentStep;
  final bool completed;

  factory V3DailyChallenge.fromJson(
    Map<String, dynamic> json, {
    required bool remote,
  }) {
    final lessonJson = (json['lesson'] as Map).cast<String, dynamic>();
    final attempt = json['attempt'] is Map
        ? (json['attempt'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final currentStep = (attempt['current_step'] as num?)?.toInt() ?? 0;
    return V3DailyChallenge(
      id: json['id'] as String,
      level: (json['level'] as String? ?? 'a1').toLowerCase(),
      primarySkill: json['primary_skill'] as String? ?? 'Practice',
      title: json['title'] as String? ?? lessonJson['title'] as String,
      summary: json['summary'] as String? ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 5,
      steps: (json['steps'] as List? ?? const ['Start challenge'])
          .cast<String>(),
      lesson: V3Lesson.fromJson(lessonJson),
      remote: remote,
      attemptId: attempt['id'] as String?,
      currentStep: currentStep.clamp(0, lessonJsonSteps(lessonJson) - 1),
      completed: attempt['status'] == 'completed',
    );
  }

  static int lessonJsonSteps(Map<String, dynamic> json) =>
      (json['steps'] as List).length;

  V3DailyChallenge withProgress({
    String? attemptId,
    int? currentStep,
    bool? completed,
  }) => V3DailyChallenge(
    id: id,
    level: level,
    primarySkill: primarySkill,
    title: title,
    summary: summary,
    minutes: minutes,
    steps: steps,
    lesson: lesson,
    remote: remote,
    attemptId: attemptId ?? this.attemptId,
    currentStep: currentStep ?? this.currentStep,
    completed: completed ?? this.completed,
  );
}
