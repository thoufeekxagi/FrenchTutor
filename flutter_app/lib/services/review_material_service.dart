import 'package:sqlite3/common.dart';

import '../data/database/storage_service.dart';
import '../models/profile.dart';
import 'universal_learning_data_service.dart';

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

/// The bounded input for one Review activity.
///
/// Review is deliberately a small projection of the universal learner
/// snapshot, not a second learner model. The snapshot still contains all
/// recent Course, Practice, Live, writing, vocabulary, competency, and exam
/// signals; this plan orders them by what should be retrieved first and adds
/// the selected output mode.
class PersonalizedReviewPlan {
  const PersonalizedReviewPlan({
    required this.snapshot,
    required this.mode,
    required this.levelBand,
    required this.learnerGoal,
    required this.interests,
    required this.topic,
    required this.retrievalTargets,
    required this.hardSignals,
  });

  final UniversalLearningSnapshot snapshot;
  final String mode;
  final String levelBand;
  final String learnerGoal;
  final List<String> interests;
  final String topic;
  final List<String> retrievalTargets;
  final List<String> hardSignals;

  List<String> get sourceSessionIds => snapshot.sourceSessionIds;

  bool get hasEvidence => snapshot.hasEvidence;

  String get focusLabel {
    if (hardSignals.isNotEmpty) {
      return 'Repair first: ${hardSignals.first}';
    }
    if (retrievalTargets.isNotEmpty) {
      return 'Bring back: ${retrievalTargets.take(2).join(' · ')}';
    }
    return 'Build from your recent French practice';
  }

  /// Prompt context shared by the four Review modes. The selected mode only
  /// changes the activity contract; the learner evidence remains identical.
  String get contextPrompt {
    final hard = hardSignals.isEmpty
        ? '(no explicit hard signal yet)'
        : hardSignals.take(6).map((value) => '- $value').join('\n');
    final retrieval = retrievalTargets.isEmpty
        ? '(no learner phrase captured yet)'
        : retrievalTargets.take(8).map((value) => '- $value').join('\n');
    final activity = switch (mode) {
      'reading' =>
        'Write a short reading passage with comprehension checks that make the learner retrieve the targets.',
      'listening' =>
        'Write a short spoken-first listening passage with replayable phrases, dictation, and comprehension checks.',
      'writing' =>
        'Create one level-appropriate writing task that requires the learner to use the targets in their own words.',
      _ =>
        'Run a one-turn-at-a-time speaking situation that makes the learner produce the targets without a script.',
    };
    final evidence = snapshot.compactContext;
    return _bounded('''
PERSONALIZED REVIEW CONTRACT
MODE: ${mode.toUpperCase()}
LEVEL: $levelBand
LEARNER GOAL: ${learnerGoal.trim().isEmpty ? 'everyday French' : learnerGoal}
ONBOARDING INTERESTS: ${interests.isEmpty ? '(none selected)' : interests.take(8).join('; ')}
PRIMARY REVIEW THEME: $topic
ACTIVITY: $activity

PEDAGOGY:
- 60% retrieval: bring back difficult, due, recently learned, or repeated language.
- 40% controlled novelty: add a small next-step challenge in the same situation.
- Every activity must use at least one retrieval target and one small new challenge.
- Reuse meaning across skills when useful, but do not copy a transcript or repeat a whole lesson.
- Never claim that a learner made an error unless the evidence below supports it.

HIGHEST-PRIORITY REPAIR SIGNALS:
$hard

RETRIEVAL TARGETS:
$retrieval

UNIVERSAL LEARNER EVIDENCE (last ${UniversalLearningDataService.defaultSessionLimit} completed sessions plus recent structured results):
$evidence

SOURCE IDS (internal provenance only; never show these to the learner):
${sourceSessionIds.take(24).join(', ')}
''', 4800);
  }

  static String _bounded(String value, int maxCharacters) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxCharacters) return clean;
    return '${clean.substring(0, maxCharacters - 1).trimRight()}…';
  }
}

abstract final class ReviewMaterialService {
  /// A review should have enough history to feel personal without turning
  /// into a replay of the entire account. Twenty completed sessions gives
  /// the generator a useful mix while remaining small enough for prompts.
  static const defaultSessionLimit =
      UniversalLearningDataService.defaultSessionLimit;

  /// Builds the new Review input from the same universal evidence used by
  /// Course. The previous 20 sessions are the window, while structured weak
  /// signals are placed ahead of ordinary recent summaries.
  static PersonalizedReviewPlan buildPersonalizedPlan({
    required CommonDatabase db,
    required Profile profile,
    required String mode,
    int sessionLimit = UniversalLearningDataService.defaultSessionLimit,
  }) {
    final snapshot = UniversalLearningDataService.buildSnapshot(
      db,
      profile,
      sessionLimit: sessionLimit,
    );
    final normalizedMode = mode.trim().toLowerCase();
    final normalized =
        const {
          'speaking',
          'reading',
          'listening',
          'writing',
        }.contains(normalizedMode)
        ? normalizedMode
        : 'speaking';
    final level = _reviewLevel(profile.level);
    final topic = snapshot.recentTopics.isEmpty
        ? (profile.interests.isEmpty
              ? _fallbackTopic(normalized)
              : profile.interests.first.trim())
        : snapshot.recentTopics.first;
    final hardSignals = _unique([
      ...snapshot.repeatedMistakes,
      ...snapshot.vocabularySignals.where(
        (value) => RegExp(
          r'\((again|hard|due)\)',
          caseSensitive: false,
        ).hasMatch(value),
      ),
      ...snapshot.performanceSignals.where(_looksWeak),
      ...snapshot.writingSignals.where(
        (value) => value.toLowerCase().contains('feedback:'),
      ),
    ], limit: 8);
    final retrievalTargets = _unique([
      ...snapshot.targetPhrases,
      ...snapshot.recentTopics,
    ], limit: 10);
    return PersonalizedReviewPlan(
      snapshot: snapshot,
      mode: normalized,
      levelBand: level,
      learnerGoal: profile.goal,
      interests: List<String>.unmodifiable(profile.interests),
      topic: topic,
      retrievalTargets: retrievalTargets,
      hardSignals: hardSignals,
    );
  }

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

  static String _reviewLevel(String raw) {
    final normalized = raw.trim().toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2'}.contains(normalized)
        ? normalized.toUpperCase()
        : 'A2';
  }

  static String _fallbackTopic(String mode) => switch (mode) {
    'reading' => 'a useful everyday situation',
    'listening' => 'a short everyday conversation',
    'writing' => 'a useful everyday message',
    _ => 'a useful everyday conversation',
  };

  static bool _looksWeak(String value) {
    final lower = value.toLowerCase();
    return lower.contains('again') ||
        lower.contains('hard') ||
        lower.contains('weak') ||
        lower.contains('not_observed') ||
        RegExp(r'\bscore\s+0(?:\.\d+)?\b').hasMatch(lower) ||
        RegExp(r'\bscore\s+0\.[0-5]').hasMatch(lower);
  }

  static List<String> _unique(Iterable<String> values, {required int limit}) {
    final result = <String>[];
    for (final value in values) {
      final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty || result.contains(clean)) continue;
      result.add(clean);
      if (result.length == limit) break;
    }
    return result;
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
