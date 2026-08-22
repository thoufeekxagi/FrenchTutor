import '../data/database/storage_service.dart';

/// A compact record of one completed practice session.
///
/// Review is intentionally built from these summaries instead of individual
/// transcript messages. This keeps the review focused on what the learner
/// practised and learned across sessions, not on a copied conversation.
class ReviewSessionSummary {
  const ReviewSessionSummary({
    required this.sessionId,
    required this.skill,
    required this.topic,
    required this.summary,
    required this.occurredAt,
  });

  final String sessionId;
  final String skill;
  final String topic;
  final String summary;
  final DateTime occurredAt;

  String get displayTitle => topic.trim().isEmpty ? skill : topic.trim();
}

abstract final class ReviewMaterialService {
  /// A review should have enough history to feel personal without turning
  /// into a replay of the entire account. Fifteen completed sessions gives
  /// the generator a useful mix while remaining small enough for prompts.
  static const defaultSessionLimit = 15;

  /// Returns the newest completed practice sessions, newest first.
  ///
  /// AI recap notes are preferred because they describe the useful language
  /// from a session. The saved session summary is used when an ambient recap
  /// has not finished yet. Neither path reads transcript turns.
  static List<ReviewSessionSummary> recentSessions(
    StorageService storage, {
    int limit = defaultSessionLimit,
  }) {
    final recapBySession = <String, String>{};
    for (final note in storage.getAllNotes()) {
      if (note.source != 'ai' || note.sessionId == null) continue;
      final text = _clean(note.text);
      if (text.isNotEmpty) {
        recapBySession.putIfAbsent(note.sessionId!, () => text);
      }
    }

    final summaries = <ReviewSessionSummary>[];
    for (final session in storage.getAllSessions()) {
      if (summaries.length == limit) break;
      if (session.endedAt == null) continue;
      if (!_isPracticeStage(session.stage)) continue;
      final recordedSummary = _clean(
        recapBySession[session.id] ?? session.summary ?? '',
      );
      final skill = _skillLabel(session.stage);
      final summary = recordedSummary.isEmpty
          ? 'Completed a $skill practice session${session.topic?.trim().isNotEmpty == true ? ' about ${_clean(session.topic!)}' : ''}.'
          : recordedSummary;
      final occurredAt =
          DateTime.tryParse(session.endedAt!) ??
          DateTime.tryParse(session.startedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      summaries.add(
        ReviewSessionSummary(
          sessionId: session.id,
          skill: skill,
          topic: _clean(session.topic ?? ''),
          summary: summary,
          occurredAt: occurredAt,
        ),
      );
    }
    return summaries;
  }

  /// Creates bounded context for story, listening, roleplay, or speaking
  /// generation. It contains only session-level summaries.
  static String promptContext(
    List<ReviewSessionSummary> sessions, {
    int maxCharacters = 1800,
  }) {
    final lines = <String>[];
    for (final session in sessions) {
      final line =
          '- ${session.skill} · ${session.displayTitle}: ${session.summary}';
      final candidate = [...lines, line].join('\n');
      if (candidate.length > maxCharacters) break;
      lines.add(line);
    }
    return lines.join('\n');
  }

  /// Mode-specific instructions shared by Course review and Practice review.
  /// The recent summaries are deliberately the only learner-history input;
  /// the selected mode controls the new activity that is generated.
  static String modePrompt(
    String mode,
    List<ReviewSessionSummary> sessions, {
    String level = 'A2',
  }) {
    final normalized = mode.toLowerCase();
    final modeInstructions = switch (normalized) {
      'reading' =>
        'Create a short reading lesson with a realistic French passage, '
            'clear comprehension questions, and explanations matched to $level.',
      'listening' =>
        'Create a short listening lesson with natural but level-matched '
            'French, comprehension questions, and useful replayable phrases.',
      'speaking' =>
        'Create a guided speaking review. Reuse the learner\'s recent themes '
            'and weak points, ask one turn at a time, and give one useful '
            'correction after each response. Keep it at $level.',
      _ => 'Create a focused French review at $level.',
    };
    return '''
REVIEW MODE: ${normalized.toUpperCase()}
$modeInstructions
This is a new personalized review, not a transcript replay. Select the most
useful language from the learner's recent completed sessions below. Avoid
repeating a whole session or inventing unrelated topics.

RECENT LEARNING HISTORY:
${promptContext(sessions)}
'''
        .trim();
  }

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _skillLabel(String? stage) => switch (stage) {
    'reading' || 'story' => 'Reading',
    'reading_listening' => 'Listening',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'grammar' => 'Grammar',
    'vocab' => 'Vocabulary',
    'speaking' ||
    'speaking_guided' ||
    'free_talk' ||
    'speaking_exam' ||
    'picture_description' ||
    'pronunciation_repair' => 'Speaking',
    'exam_reading' => 'Exam reading',
    'exam_listening' => 'Exam listening',
    'exam_writing' => 'Exam writing',
    'exam_speaking' => 'Exam speaking',
    _ => 'Practice',
  };

  static bool _isPracticeStage(String? stage) => const {
    'reading',
    'story',
    'reading_listening',
    'roleplay',
    'writing',
    'grammar',
    'vocab',
    'alphabet',
    'speaking',
    'speaking_guided',
    'free_talk',
    'speaking_exam',
    'picture_description',
    'pronunciation_repair',
    'exam_reading',
    'exam_listening',
    'exam_writing',
    'exam_speaking',
    'review',
  }.contains(stage);
}
