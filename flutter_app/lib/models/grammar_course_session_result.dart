/// Result returned when a Grammar course session closes.
class GrammarCourseSessionResult {
  const GrammarCourseSessionResult({
    required this.sessionId,
    required this.correct,
    required this.attempted,
    required this.completed,
  });

  final String sessionId;
  final int correct;
  final int attempted;
  final bool completed;
}
