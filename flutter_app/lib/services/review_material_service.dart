import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../data/database/storage_service.dart';
import '../models/profile.dart';
import 'universal_learning_data_service.dart';

/// A compact record of one completed practice session.
///
/// Review is built from a compact session summary plus bounded saved material.
/// The material is enough to identify the actual exercise without replaying a
/// full conversation or allowing history to grow the prompt unboundedly.
class ReviewSessionSummary {
  const ReviewSessionSummary({
    required this.sessionId,
    required this.skill,
    required this.topic,
    required this.summary,
    required this.occurredAt,
    this.details = const [],
  });

  final String sessionId;
  final String skill;
  final String topic;
  final String summary;
  final DateTime occurredAt;

  /// Bounded learner-facing material captured from the saved turns and, for
  /// Course sessions, the generated lesson artifact.  Keeping it on the
  /// projection means Review can render the actual exercise rather than only
  /// its heading without loading a second history model.
  final List<String> details;

  String get displayTitle => topic.trim().isEmpty ? skill : topic.trim();

  /// Course completion rows intentionally keep a stable generic summary for
  /// history analytics.  The Review UI should lead with the actual saved
  /// lesson material when that summary is all it contains.
  String get displaySummary {
    final generic = summary.startsWith('Completed the course session:');
    if (!generic || details.isEmpty) return summary;
    // Typed Course activities persist a compact material snapshot as one
    // assistant turn. Prefer its lesson line over the transcript wrapper so
    // the Review card shows the actual generated lesson title.
    for (final detail in details) {
      final clean = detail
          .replaceFirst(RegExp(r'^Tutor: Course lesson material:\s*'), '')
          .trim();
      if (clean.startsWith('Lesson:')) return clean;
    }
    return details.first;
  }
}

class ReviewTarget {
  const ReviewTarget({
    required this.key,
    required this.type,
    required this.text,
    required this.reason,
    required this.priority,
    this.sourceIds = const [],
    this.evidence = const {},
  });

  final String key;
  final String type;
  final String text;
  final String reason;
  final double priority;
  final List<String> sourceIds;
  final Map<String, dynamic> evidence;

  Map<String, dynamic> toJson() => {
    'key': key,
    'type': type,
    'text': text,
    'reason': reason,
    'priority': priority,
    'sourceIds': sourceIds,
    'evidence': evidence,
  };
}

class ReviewSpeakingTarget {
  const ReviewSpeakingTarget({
    required this.french,
    required this.english,
    this.tip = '',
  });

  final String french;
  final String english;
  final String tip;

  Map<String, dynamic> toJson() => {
    'french': french,
    'english': english,
    if (tip.trim().isNotEmpty) 'tip': tip,
  };
}

/// The model-authored handoff between learner-history analysis and the
/// existing lesson engines. It is persisted with the Review plan so the same
/// reasoning can be inspected, resumed, and reused without re-sending history.
class ReviewBlueprint {
  const ReviewBlueprint({
    required this.mode,
    required this.title,
    required this.topic,
    required this.summary,
    required this.rationale,
    required this.contextPrompt,
    required this.objectives,
    required this.vocabulary,
    required this.grammar,
    required this.steps,
    required this.sourceSessionIds,
    this.speakingTargets = const [],
  });

  final String mode;
  final String title;
  final String topic;
  final String summary;
  final String rationale;
  final String contextPrompt;
  final List<String> objectives;
  final List<String> vocabulary;
  final List<String> grammar;
  final List<String> steps;
  final List<String> sourceSessionIds;
  final List<ReviewSpeakingTarget> speakingTargets;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'title': title,
    'topic': topic,
    'summary': summary,
    'rationale': rationale,
    'contextPrompt': contextPrompt,
    'objectives': objectives,
    'vocabulary': vocabulary,
    'grammar': grammar,
    'steps': steps,
    'sourceSessionIds': sourceSessionIds,
    'speakingTargets': speakingTargets
        .map((target) => target.toJson())
        .toList(),
  };

  /// Only this compact teaching handoff reaches the selected Review activity.
  /// It intentionally excludes internal source ids and raw data.
  String get teachingContext => [
    'REVIEW BLUEPRINT',
    if (title.isNotEmpty) 'TITLE: $title',
    if (topic.isNotEmpty) 'THEME: $topic',
    if (summary.isNotEmpty) 'PURPOSE: $summary',
    if (rationale.isNotEmpty) 'WHY THIS REVIEW: $rationale',
    if (objectives.isNotEmpty) 'OBJECTIVES: ${objectives.join('; ')}',
    if (vocabulary.isNotEmpty) 'PRIORITY VOCABULARY: ${vocabulary.join('; ')}',
    if (grammar.isNotEmpty) 'PRIORITY GRAMMAR: ${grammar.join('; ')}',
    if (steps.isNotEmpty) 'LESSON ARC: ${steps.join(' | ')}',
    if (speakingTargets.isNotEmpty)
      'SPEAKING TARGETS: ${speakingTargets.map((target) => '${target.french} = ${target.english}').join('; ')}',
    if (contextPrompt.isNotEmpty) 'TEACHING CONTRACT: $contextPrompt',
  ].join('\n');
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
    this.kind = 'review',
    this.requestedMode = 'smart',
    this.durationMinutes = 10,
    this.targets = const [],
    this.futureSessionId,
    this.futureSessionIds = const [],
    this.futureLessonSummaries = const [],
    this.futureContext,
  });

  final UniversalLearningSnapshot snapshot;
  final String mode;
  final String levelBand;
  final String learnerGoal;
  final List<String> interests;
  final String topic;
  final List<String> retrievalTargets;
  final List<String> hardSignals;
  final String kind;
  final String requestedMode;
  final int durationMinutes;
  final List<ReviewTarget> targets;
  final String? futureSessionId;

  /// IDs for the bounded forward Course window. [futureSessionId] remains as
  /// the compatibility shortcut for the first lesson in that window.
  final List<String> futureSessionIds;

  /// Learner-facing labels for the same bounded future window used by the
  /// planner. The full content remains in [futureContext].
  final List<String> futureLessonSummaries;
  final String? futureContext;

  List<String> get sourceSessionIds => snapshot.sourceSessionIds;

  bool get hasEvidence => snapshot.hasEvidence;

  String get focusLabel {
    if (kind == 'warmup' &&
        futureContext != null &&
        futureContext!.isNotEmpty) {
      return 'Preview next: $topic';
    }
    if (hardSignals.isNotEmpty) {
      return 'Repair first: ${hardSignals.first}';
    }
    if (retrievalTargets.isNotEmpty) {
      return 'Bring back: ${retrievalTargets.take(2).join(' · ')}';
    }
    return 'Build from your recent French practice';
  }

  Map<String, dynamic> get briefJson => {
    'version': 1,
    'kind': kind,
    'requestedMode': requestedMode,
    'resolvedMode': mode,
    'levelBand': levelBand,
    'goal': learnerGoal,
    'durationMinutes': durationMinutes,
    'topic': topic,
    'sourceFingerprint': snapshot.fingerprint,
    'sourceSessionIds': sourceSessionIds.take(40).toList(growable: false),
    'courseSessionCount': snapshot.courseSessionCount,
    'practiceSessionCount': snapshot.practiceSessionCount,
    'targets': targets.map((target) => target.toJson()).toList(growable: false),
    'futureSessionId': futureSessionId,
    'futureSessionIds': futureSessionIds,
    'futureLessonSummaries': futureLessonSummaries,
    'futureContext': futureContext,
    'compactContext': snapshot.compactContext,
  };

  /// Prompt context shared by the four Review modes. The selected mode only
  /// changes the activity contract; the learner evidence remains identical.
  String get contextPrompt {
    final hard = hardSignals.isEmpty
        ? '(no explicit hard signal yet)'
        : hardSignals.take(5).map((value) => '- $value').join('\n');
    final retrieval = retrievalTargets.isEmpty
        ? '(no learner phrase captured yet)'
        : retrievalTargets.take(5).map((value) => '- $value').join('\n');
    final activity = switch (mode) {
      'smart' =>
        'Build one mixed review lesson using vocabulary, grammar, reading, listening, writing, and a short guided speaking drill. Do not open Live audio, roleplay, or Free Talk.',
      'reading' =>
        'Write a short reading passage with comprehension checks that make the learner retrieve the targets.',
      'listening' =>
        'Write a short spoken-first listening passage with replayable phrases, dictation, and comprehension checks.',
      'writing' =>
        'Create one level-appropriate writing task that requires the learner to use the targets in their own words.',
      _ =>
        'Run a one-turn-at-a-time speaking situation that makes the learner produce the targets without a script.',
    };
    // Targets and repair signals already carry the useful vocabulary and
    // mistake evidence. Only include complementary support here so the same
    // phrases are not paid for twice in the Live context.
    final evidence = _supportingEvidence;
    final targetBrief = targets.isEmpty
        ? '(none; use the evidence conservatively)'
        : targets
              .take(6)
              .map(
                (target) =>
                    '- ${target.text} [${target.type}; priority ${target.priority.toStringAsFixed(2)}] — ${target.reason}',
              )
              .join('\n');
    final direction = kind == 'warmup'
        ? '''WARM-UP DIRECTION:
- Use the bounded Course window below: recent completed material is a bridge,
  and the upcoming lessons are preview material, not mastered evidence.
- Look forward across the available upcoming lessons, not just the first title.
- Teach two to four useful items and one tiny production check.
- Do not mark future material as mastered or claim the learner completed it.
COURSE WINDOW CONTEXT:
${futureContext ?? '(no planned Course lesson was available; make a conservative preview)'}'''
        : '''REVIEW DIRECTION:
- Look backward at completed Course and Practice evidence.
- Teach what was missed, due, weakly retained, or important but under-practised.''';
    return _bounded('''
PERSONALIZED ${kind.toUpperCase()} CONTRACT
MODE: ${mode.toUpperCase()}
LEVEL: $levelBand
LEARNER GOAL: ${learnerGoal.trim().isEmpty ? 'everyday French' : learnerGoal}
ONBOARDING INTERESTS: ${interests.isEmpty ? '(none selected)' : interests.take(4).join('; ')}
PRIMARY REVIEW THEME: $topic
ACTIVITY: $activity

$direction

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

RANKED TARGET RECORDS:
$targetBrief

UNIVERSAL LEARNER EVIDENCE (selected signals from the recent completed window):
$evidence
''', ReviewMaterialService.reviewLiveContextCharacterBudget);
  }

  /// Structured dossier for GPT's review-composer call. This is intentionally
  /// richer than the Live handoff: GPT needs enough recent Course and Practice
  /// evidence to choose what matters, while the tutor only needs the final
  /// blueprint. It contains summaries and bounded excerpts, never raw audio.
  Map<String, dynamic> get gptDossier => {
    'version': 2,
    'request': {
      'kind': kind,
      'requestedMode': requestedMode,
      'localSuggestedMode': mode,
      'primaryTopic': topic,
      'durationMinutes': durationMinutes,
      'futureSessionId': futureSessionId,
      'futureSessionIds': futureSessionIds,
      'futureLessonSummaries': futureLessonSummaries,
      'futureCourseContext': futureContext,
    },
    'learner': {
      'level': levelBand,
      'goal': learnerGoal,
      'interests': interests.take(8).toList(growable: false),
    },
    'courseAndPracticeCoverage': {
      'courseSessions': snapshot.courseSessionCount,
      'practiceSessions': snapshot.practiceSessionCount,
      'sourceSessionIds': sourceSessionIds.take(40).toList(growable: false),
    },
    'recentSessions': snapshot.evidence
        .take(20)
        .map(
          (item) => {
            'id': item.id,
            'source': item.source,
            'skill': item.mode,
            'topic': item.topic,
            'summary': item.summary,
            'details': item.details.take(8).toList(growable: false),
            'occurredAt': item.occurredAt.toUtc().toIso8601String(),
          },
        )
        .toList(growable: false),
    'recentLearnerTranscriptExcerpts': snapshot.transcriptExcerpts
        .take(12)
        .toList(growable: false),
    'vocabularyEvidence': snapshot.vocabularySignals
        .take(24)
        .toList(growable: false),
    'learnerPhrases': snapshot.targetPhrases.take(24).toList(growable: false),
    'repeatedMistakes': snapshot.repeatedMistakes
        .take(12)
        .toList(growable: false),
    'performanceSignals': snapshot.performanceSignals
        .take(32)
        .toList(growable: false),
    'writingEvidence': snapshot.writingSignals.take(8).toList(growable: false),
    'examEvidence': snapshot.examSignals.take(8).toList(growable: false),
    'localSignals': {
      'retrievalTargets': retrievalTargets.take(8).toList(growable: false),
      'hardSignals': hardSignals.take(8).toList(growable: false),
      'recentTopics': snapshot.recentTopics.take(12).toList(growable: false),
      'primaryTopic': topic,
    },
  };

  String get _supportingEvidence {
    final lines = <String>[];
    if (snapshot.recentTopics.isNotEmpty) {
      lines.add(
        'Recent situations: ${snapshot.recentTopics.take(3).join('; ')}.',
      );
    }
    if (snapshot.performanceSignals.isNotEmpty) {
      lines.add(
        'Recent results: ${snapshot.performanceSignals.take(3).join('; ')}.',
      );
    }
    if (snapshot.writingSignals.isNotEmpty) {
      lines.add(
        'Writing evidence: ${snapshot.writingSignals.take(2).join('; ')}.',
      );
    }
    if (snapshot.examSignals.isNotEmpty) {
      lines.add('Exam evidence: ${snapshot.examSignals.take(2).join('; ')}.');
    }
    if (snapshot.transcriptExcerpts.isNotEmpty) {
      lines.add(
        'Learner transcript excerpts: ${snapshot.transcriptExcerpts.take(2).map((value) => '"$value"').join('; ')}.',
      );
    }
    if (lines.isEmpty) return '(no additional supporting evidence)';
    return ReviewMaterialService._bounded(lines.join('\n'), 2600);
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

  /// Dynamic context budget for a Review/Warm-up Live handoff. At typical
  /// French/English tokenization this is a roughly 2k–4k-token envelope once
  /// the tutor system prompt and learner profile are included.
  static const reviewLiveContextCharacterBudget = 10000;

  /// Warm-up is intentionally a small rolling window: a few completed Course
  /// lessons provide the bridge, and a few generated lessons provide the
  /// forward preview. Keeping both sides bounded prevents the Live prompt
  /// from becoming a hidden history dump as a learner advances.
  static const warmupCompletedSessionLimit = 3;
  static const warmupFutureSessionLimit = 3;

  /// Builds the new Review input from the same universal evidence used by
  /// Course. The previous 20 sessions are the window, while structured weak
  /// signals are placed ahead of ordinary recent summaries.
  static PersonalizedReviewPlan buildPersonalizedPlan({
    required CommonDatabase db,
    required Profile profile,
    required String mode,
    int sessionLimit = UniversalLearningDataService.defaultSessionLimit,
    String kind = 'review',
    int durationMinutes = 10,
  }) {
    final snapshot = UniversalLearningDataService.buildSnapshot(
      db,
      profile,
      sessionLimit: sessionLimit,
    );
    final normalizedMode = mode.trim().toLowerCase();
    final requestedMode = mode.trim().toLowerCase();
    final normalized =
        const {
          'speaking',
          'reading',
          'listening',
          'writing',
        }.contains(normalizedMode)
        ? normalizedMode
        : 'smart';
    final level = _reviewLevel(profile.level);
    // A Review theme is a retrieval anchor, not a new roleplay setting.
    // Using the first historical session title here made Smart Review inherit
    // stock topics such as “At the station” even when the actual targets were
    // grammar or vocabulary. The composer still receives the full bounded
    // evidence dossier, but the Live handoff gets this neutral anchor.
    final topic = _reviewAnchor(normalized);
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
    // Historical session titles are provenance, not learner targets. A Review
    // must not promote a title such as “At the station” into the speaking
    // prompt just because it was present in recent history.
    final retrievalTargets = _unique(snapshot.targetPhrases, limit: 10);
    final targets = _rankReviewTargets(snapshot);
    return PersonalizedReviewPlan(
      snapshot: snapshot,
      mode: normalized,
      levelBand: level,
      learnerGoal: profile.goal,
      interests: List<String>.unmodifiable(profile.interests),
      topic: topic,
      retrievalTargets: retrievalTargets,
      hardSignals: hardSignals,
      kind: kind,
      requestedMode: requestedMode.isEmpty ? 'smart' : requestedMode,
      durationMinutes: durationMinutes,
      targets: targets,
    );
  }

  /// Builds a short future-facing plan from a bounded Course window. Completed
  /// Course evidence is used as a bridge and up to three active/planned rows
  /// supply the forward preview. If Course has not been generated yet, the
  /// same planner still returns a safe warm-up from recent targets/profile.
  static PersonalizedReviewPlan buildWarmupPlan({
    required CommonDatabase db,
    required Profile profile,
    required String mode,
    int durationMinutes = 5,
    int sessionLimit = UniversalLearningDataService.defaultSessionLimit,
  }) {
    final snapshot = UniversalLearningDataService.buildSnapshot(
      db,
      profile,
      sessionLimit: sessionLimit,
    );
    final upcoming = _upcomingCoursePreviews(
      db,
      limit: warmupFutureSessionLimit,
    );
    final next = upcoming.isEmpty ? null : upcoming.first;
    final requestedMode = mode.trim().toLowerCase();
    final futureMode = _modeFromSkill(next?['primarySkill']?.toString());
    final resolvedMode =
        const {
          'speaking',
          'reading',
          'listening',
          'writing',
        }.contains(requestedMode)
        ? requestedMode
        : futureMode ?? _smartMode(snapshot);
    final topic = _clean(
      next?['title']?.toString() ??
          (snapshot.recentTopics.isEmpty
              ? (profile.interests.isEmpty
                    ? _fallbackTopic(resolvedMode)
                    : profile.interests.first)
              : snapshot.recentTopics.first),
    );
    final futureContext = _warmupContext(snapshot, upcoming);
    final targets = _rankWarmupTargets(snapshot, upcoming);
    return PersonalizedReviewPlan(
      snapshot: snapshot,
      mode: resolvedMode,
      levelBand: _reviewLevel(profile.level),
      learnerGoal: profile.goal,
      interests: List<String>.unmodifiable(profile.interests),
      topic: topic.isEmpty ? _fallbackTopic(resolvedMode) : topic,
      retrievalTargets: targets
          .map((target) => target.text)
          .toList(growable: false),
      hardSignals: const [],
      kind: 'warmup',
      requestedMode: requestedMode.isEmpty ? 'smart' : requestedMode,
      durationMinutes: durationMinutes,
      targets: targets,
      futureSessionId: next?['id'] as String?,
      futureSessionIds: upcoming
          .map((lesson) => lesson['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      futureLessonSummaries: upcoming
          .map(_warmupLessonSummary)
          .where((summary) => summary.isNotEmpty)
          .toList(growable: false),
      futureContext: futureContext,
    );
  }

  static String _smartMode(UniversalLearningSnapshot snapshot) {
    // Smart is a composite lesson. It must not silently become speaking or
    // open a Live audio session.
    final scores = <String, int>{
      'speaking': snapshot.repeatedMistakes.length * 2,
      'writing': snapshot.writingSignals.length * 3,
      'reading': 0,
      'listening': 0,
    };
    for (final signal in [
      ...snapshot.performanceSignals,
      ...snapshot.examSignals,
      ...snapshot.recentTopics,
    ]) {
      final lower = signal.toLowerCase();
      for (final mode in const [
        'speaking',
        'writing',
        'reading',
        'listening',
      ]) {
        if (lower.contains(mode)) scores[mode] = scores[mode]! + 2;
      }
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.value > 0 ? ranked.first.key : 'smart';
  }

  static String _reviewAnchor(String mode) => switch (mode) {
    'reading' => 'recent French reading targets',
    'listening' => 'recent French listening targets',
    'writing' => 'recent French writing targets',
    _ => 'recent French vocabulary and grammar targets',
  };

  static String? _modeFromSkill(String? skill) {
    final normalized = (skill ?? '').toLowerCase();
    if (normalized.contains('listen')) return 'listening';
    if (normalized.contains('read')) return 'reading';
    if (normalized.contains('writ')) return 'writing';
    if (normalized.contains('speak')) return 'speaking';
    return null;
  }

  static List<ReviewTarget> _rankReviewTargets(
    UniversalLearningSnapshot snapshot,
  ) {
    final result = <ReviewTarget>[];
    void add(
      String text, {
      required String type,
      required String reason,
      required double priority,
    }) {
      final clean = _clean(text);
      if (clean.isEmpty || result.any((target) => target.text == clean)) return;
      result.add(
        ReviewTarget(
          key: UniversalLearningDataService.stableHash('$type|$clean'),
          type: type,
          text: clean,
          reason: reason,
          priority: priority,
          sourceIds: snapshot.sourceSessionIds.take(8).toList(growable: false),
        ),
      );
    }

    for (final value in snapshot.repeatedMistakes) {
      add(
        value,
        type: 'repair',
        reason: 'repeated mistake signal',
        priority: 1.0,
      );
    }
    for (final value in snapshot.vocabularySignals.where(
      (value) =>
          RegExp(r'\((again|hard|due)', caseSensitive: false).hasMatch(value),
    )) {
      add(
        value,
        type: 'vocabulary',
        reason: 'due or difficult recall',
        priority: .92,
      );
    }
    for (final value in snapshot.targetPhrases) {
      add(
        value,
        type: 'phrase',
        reason: 'learner-produced or recently learned',
        priority: .72,
      );
    }
    for (final value in snapshot.performanceSignals.where(_looksWeak)) {
      add(
        value,
        type: 'performance',
        reason: 'weak structured result',
        priority: .82,
      );
    }
    for (final value in snapshot.recentTopics) {
      add(
        value,
        type: 'context',
        reason: 'recent context for transfer',
        priority: .38,
      );
    }
    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result.take(12).toList(growable: false);
  }

  static List<ReviewTarget> _rankWarmupTargets(
    UniversalLearningSnapshot snapshot,
    List<Map<String, dynamic>> upcoming,
  ) {
    final result = <ReviewTarget>[];
    final sourceIds = <String>[
      ...upcoming.map((lesson) => lesson['id']).whereType<String>(),
      ...snapshot.sourceSessionIds.take(6),
    ];
    void add(String text, String type, double priority, String reason) {
      final clean = _clean(text);
      if (clean.isEmpty || result.any((target) => target.text == clean)) return;
      result.add(
        ReviewTarget(
          key: UniversalLearningDataService.stableHash('warmup|$type|$clean'),
          type: type,
          text: clean,
          reason: reason,
          priority: priority,
          sourceIds: sourceIds,
        ),
      );
    }

    for (var index = 0; index < upcoming.length; index++) {
      final lesson = upcoming[index];
      final rank = index == 0
          ? 0
          : index == 1
          ? -.04
          : -.08;
      for (final phrase in (lesson['targetPhrases'] as List? ?? const [])) {
        add(
          phrase.toString(),
          'future_phrase',
          .95 + rank,
          'upcoming Course lesson ${index + 1} target',
        );
      }
      for (final grammar in (lesson['grammar'] as List? ?? const [])) {
        add(
          grammar.toString(),
          'future_grammar',
          .88 + rank,
          'upcoming Course lesson ${index + 1} grammar',
        );
      }
      for (final success in (lesson['successCriteria'] as List? ?? const [])) {
        add(
          success.toString(),
          'future_success',
          .72 + rank,
          'upcoming Course lesson ${index + 1} success criterion',
        );
      }
    }
    for (final phrase in snapshot.targetPhrases) {
      add(
        phrase,
        'retrieval_bridge',
        .55,
        'bridge from recent learner language',
      );
    }
    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result.take(12).toList(growable: false);
  }

  static List<Map<String, dynamic>> _upcomingCoursePreviews(
    CommonDatabase db, {
    int limit = warmupFutureSessionLimit,
  }) {
    try {
      final rows = db.select(
        '''SELECT id, title, subtitle, context, primary_skill,
                  grammar_focus_json, success_criteria_json,
                  target_phrases_json, artifact_json, sequence, status
           FROM adaptive_course_sessions
           WHERE deleted_at IS NULL AND status IN ('planned', 'active')
           ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, sequence
           LIMIT ?''',
        [limit.clamp(1, warmupFutureSessionLimit)],
      );
      return rows
          .map((row) {
            final artifact = _jsonMap(row['artifact_json']);
            return {
              'id': row['id']?.toString(),
              'title': _clean(row['title']?.toString() ?? ''),
              'subtitle': _clean(row['subtitle']?.toString() ?? ''),
              'context': _clean(row['context']?.toString() ?? ''),
              'primarySkill': _clean(row['primary_skill']?.toString() ?? ''),
              'grammar': _jsonList(row['grammar_focus_json']),
              'successCriteria': _jsonList(row['success_criteria_json']),
              'targetPhrases': _jsonList(row['target_phrases_json']),
              'artifact': artifact,
              'sequence': row['sequence'],
              'status': row['status'],
            };
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String? _warmupContext(
    UniversalLearningSnapshot snapshot,
    List<Map<String, dynamic>> upcoming,
  ) {
    final lines = <String>[];
    final recentCourse = snapshot.evidence
        .where((item) => item.source == 'course')
        .take(warmupCompletedSessionLimit)
        .toList(growable: false);
    if (recentCourse.isNotEmpty) {
      lines.add('RECENT COMPLETED COURSE MATERIAL (bridge only):');
      for (final item in recentCourse) {
        final details = item.details.take(3).join(' | ');
        lines.add(
          '- ${item.topic.isEmpty ? item.mode : item.topic}: '
          '${_bounded(item.summary, 260)}'
          '${details.isEmpty ? '' : ' · $details'}',
        );
      }
    }
    if (upcoming.isNotEmpty) {
      lines.add('UPCOMING COURSE WINDOW (not mastered yet):');
      for (var index = 0; index < upcoming.length; index++) {
        final lesson = upcoming[index];
        final fields = <String>[
          if ((lesson['title'] as String?)?.isNotEmpty == true)
            lesson['title'] as String,
          if ((lesson['subtitle'] as String?)?.isNotEmpty == true)
            lesson['subtitle'] as String,
          if ((lesson['context'] as String?)?.isNotEmpty == true)
            'Context: ${lesson['context']}',
          if ((lesson['primarySkill'] as String?)?.isNotEmpty == true)
            'Primary skill: ${lesson['primarySkill']}',
          if ((lesson['grammar'] as List).isNotEmpty)
            'Grammar: ${(lesson['grammar'] as List).join('; ')}',
          if ((lesson['successCriteria'] as List).isNotEmpty)
            'Success: ${(lesson['successCriteria'] as List).join('; ')}',
          if ((lesson['targetPhrases'] as List).isNotEmpty)
            'Targets: ${(lesson['targetPhrases'] as List).join('; ')}',
          if ((lesson['artifact'] as Map).isNotEmpty)
            'Generated activity: ${_bounded(jsonEncode(lesson['artifact']), 900)}',
        ];
        lines.add(
          '- Lesson ${index + 1}: ${_bounded(fields.join(' · '), 1500)}',
        );
      }
    }
    if (lines.isEmpty) return null;
    return _bounded(lines.join('\n'), 6500);
  }

  static String _warmupLessonSummary(Map<String, dynamic> lesson) {
    final title = _clean(lesson['title']?.toString() ?? '');
    final context = _clean(lesson['context']?.toString() ?? '');
    final skill = _clean(lesson['primarySkill']?.toString() ?? '');
    final grammar = (lesson['grammar'] as List? ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .take(1)
        .join();
    final target = (lesson['targetPhrases'] as List? ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .take(1)
        .join();
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (context.isNotEmpty) context,
      if (skill.isNotEmpty) skill,
      if (grammar.isNotEmpty) 'Grammar: $grammar',
      if (target.isNotEmpty) 'Target: $target',
    ];
    return _bounded(parts.join(' · '), 120);
  }

  static List<String> _jsonList(Object? raw) {
    if (raw is List) return raw.map((value) => value.toString()).toList();
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      return value is List
          ? value.map((item) => item.toString()).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> _jsonMap(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Returns the newest completed practice sessions, newest first.
  ///
  /// AI recap notes are preferred because they describe the useful language
  /// from a session. The saved session summary is used when an ambient recap
  /// has not finished yet. The bounded [ReviewSessionSummary.details] projection
  /// additionally carries saved turns and generated Course material.
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
          details: storage.getSessionReviewDetails(
            sessionId: session.id,
            contentKey: session.contentKey,
          ),
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
      final material = session.details.isEmpty
          ? session.summary
          : '${session.displaySummary} · ${session.details.first}';
      final line = '- ${session.skill} · ${session.displayTitle}: $material';
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

  static String _bounded(String value, int maxCharacters) {
    final clean = _clean(value);
    if (clean.length <= maxCharacters) return clean;
    return '${clean.substring(0, maxCharacters - 1).trimRight()}…';
  }

  static String _skillLabel(String? stage) => switch (stage) {
    'reading' || 'story' => 'Reading',
    'reading_listening' || 'listening' => 'Listening',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'grammar' => 'Grammar',
    'vocab' || 'vocabulary' => 'Vocabulary',
    'alphabet' => 'Alphabet',
    'connectors' => 'Connectors',
    'liaison' => 'Liaison',
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
    'listening',
    'roleplay',
    'writing',
    'grammar',
    'vocab',
    'vocabulary',
    'alphabet',
    'connectors',
    'liaison',
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
