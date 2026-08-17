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
  static const defaultSessionLimit = 10;

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
      final summary = _clean(
        recapBySession[session.id] ?? session.summary ?? '',
      );
      if (summary.isEmpty) continue;
      final occurredAt =
          DateTime.tryParse(session.endedAt!) ??
          DateTime.tryParse(session.startedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      summaries.add(
        ReviewSessionSummary(
          sessionId: session.id,
          skill: _skillLabel(session.stage),
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

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _skillLabel(String? stage) => switch (stage) {
    'reading' || 'story' => 'Reading',
    'reading_listening' => 'Listening',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'grammar' => 'Grammar',
    'vocab' => 'Vocabulary',
    'speaking' || 'free_talk' || 'speaking_exam' => 'Speaking',
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
    'free_talk',
    'speaking_exam',
    'exam_reading',
    'exam_listening',
    'exam_writing',
    'exam_speaking',
  }.contains(stage);
}
