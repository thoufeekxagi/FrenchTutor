import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../models/speaking_course.dart';
import '../../services/adaptive_curriculum_service.dart';
import '../../services/universal_learning_data_service.dart';
import 'app_migrations.dart';

const _adaptiveUuid = Uuid();

Map<String, dynamic>? _decodeMap(Object? value) {
  if (value == null) return null;
  if (value is Map) return value.cast<String, dynamic>();
  final decoded = jsonDecode(value.toString());
  return decoded is Map ? decoded.cast<String, dynamic>() : null;
}

/// The unit of course progression shared by onboarding, Home, Course, and
/// the speaking pathway. Foundation contains five fixed sessions and Unit 2+
/// grows one fully prepared personalized session at a time, up to five.
const adaptiveCourseFoundationSize = 5;
const adaptiveCourseBatchSize = 5;
// How many real AI-generated lessons (sequence 11+) to always try to keep
// ready beyond wherever the learner has reached — not a cap, a floor. Growth
// never stops; this only controls how far ahead the buffer stays topped up.
const adaptiveCourseLookahead = 2;
// The first two personalized batches are a gentle bridge from onboarding to
// the full practice rotation. Recent evidence can choose the situation and
// target, but it must not make these early lessons jump ahead of the learner's
// CEFR band.
const adaptiveCourseSimplePhaseEnd = 15;
const adaptiveCourseGenerationVersion = 3;

/// One planned session in the learner's current adaptive route.
///
/// The specification and its prepared artifact are persisted together. The
/// existing practice engines render that artifact but never generate it from
/// a Course tap.
class AdaptiveCourseSessionSpec {
  const AdaptiveCourseSessionSpec({
    required this.id,
    required this.planId,
    required this.contentKey,
    required this.sequence,
    required this.level,
    required this.unit,
    required this.unitTitle,
    required this.title,
    required this.subtitle,
    required this.competency,
    required this.context,
    required this.primarySkill,
    required this.supportingSkills,
    required this.grammarFocus,
    required this.successCriteria,
    required this.estimatedMinutes,
    this.targetPhrases = const [],
    this.sourceSessionIds = const [],
    this.generationStatus = 'queued',
    this.artifactKind,
    this.artifact,
    this.generationVersion = 1,
    this.generationAttempts = 0,
    this.generationError,
    required this.profileFingerprint,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String planId;
  final String contentKey;
  final int sequence;
  final String level;
  final int unit;
  final String unitTitle;
  final String title;
  final String subtitle;
  final String competency;
  final String context;
  final SpeakSkill primarySkill;
  final List<SpeakSkill> supportingSkills;
  final List<String> grammarFocus;
  final List<String> successCriteria;
  final int estimatedMinutes;
  final List<String> targetPhrases;
  final List<String> sourceSessionIds;
  final String generationStatus; // queued | generating | ready | failed
  final String? artifactKind;
  final Map<String, dynamic>? artifact;
  final int generationVersion;
  final int generationAttempts;
  final String? generationError;
  final String profileFingerprint;
  final String status; // planned | active | completed | replaced
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isFoundation => sequence <= adaptiveCourseFoundationSize;

  /// A personalized lesson is ready only when the artifact needed by its
  /// practice engine is present. Listening must never expose text-only JSON
  /// as finished: its durable PCM/WAV path is part of the same package.
  bool get isContentReady {
    if (isFoundation) return true;
    if (generationStatus != 'ready' || artifact == null) return false;
    final value = artifact!;
    final normalizedLevel = level.trim().toUpperCase();
    bool nonEmpty(Object? item) => item?.toString().trim().isNotEmpty == true;
    bool listHas(Object? item, int minimum) =>
        item is List && item.length >= minimum;
    bool safeFrench(Object? item, {int? maxWords}) {
      final french = item?.toString().trim() ?? '';
      if (french.isEmpty) return false;
      final words = french
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty);
      final limit =
          maxWords ??
          (normalizedLevel == 'A1'
              ? 10
              : normalizedLevel == 'A2'
              ? 14
              : 32);
      if ((normalizedLevel == 'A1' || normalizedLevel == 'A2') &&
          words.length > limit) {
        return false;
      }
      if (normalizedLevel == 'A1' &&
          RegExp(
            r'\b(conditionnel|subjonctif|à condition que|bien que|cependant|pourtant)\b',
            caseSensitive: false,
          ).hasMatch(french)) {
        return false;
      }
      return true;
    }

    // Real generation defect caught directly from a learner's screenshot:
    // the model can echo the English gloss into the French field too (fr
    // and en byte-identical), while id/phonetic still correctly held the
    // real French word. A learner then saw "FRENCH WORD: milk" for lait.
    // Word-count and banned-structure checks never catch this since plain
    // English words pass both. The server now rejects this at generation
    // time (see validateVocabulary in prepare-course-lesson/index.ts), but
    // this same check belongs here too so any already-stored artifact of
    // this shape is never treated as ready on-device either.
    bool notEchoedEnglish(Object? fr, Object? en) =>
        fr?.toString().trim().toLowerCase() !=
        en?.toString().trim().toLowerCase();

    bool storyHasSegments() {
      final passage = value['passage'];
      if (passage is! Map ||
          !listHas(passage['segments'], 2) ||
          !listHas(value['quiz'], 1)) {
        return false;
      }
      if (normalizedLevel != 'A1' && normalizedLevel != 'A2') return true;
      return (passage['segments'] as List).every(
        (segment) =>
            segment is Map &&
            nonEmpty(segment['en']) &&
            safeFrench(segment['fr']) &&
            notEchoedEnglish(segment['fr'], segment['en']),
      );
    }

    bool speakingLinesSafe() {
      if (value['practiceMode']?.toString() != practiceMode) return false;
      final lines = value['lines'];
      if (!listHas(lines, 3)) return false;
      final maxWords = normalizedLevel == 'A1'
          ? 8
          : normalizedLevel == 'A2'
          ? 11
          : 32;
      final seen = <String>{};
      return (lines as List).every((line) {
        if (line is! Map ||
            !nonEmpty(line['en']) ||
            !safeFrench(line['fr'], maxWords: maxWords) ||
            !notEchoedEnglish(line['fr'], line['en'])) {
          return false;
        }
        final french = line['fr'].toString().trim();
        final folded = french
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-zà-ÿ0-9 ]', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (RegExp(
          r'^(répétez|repetez|repeat|say|listen)\b',
          caseSensitive: false,
        ).hasMatch(french)) {
          return false;
        }
        if (!seen.add(folded)) return false;
        return true;
      });
    }

    bool writingCourseSafe() {
      final lesson = value['lesson'];
      if (lesson is! Map || !listHas(lesson['steps'], 3)) return false;
      return value['practiceMode']?.toString() == practiceMode &&
          lesson['mode']?.toString() == practiceMode &&
          lesson['level']?.toString().toUpperCase() == normalizedLevel;
    }

    bool grammarCourseSafe() {
      final session = value['session'];
      if (session is! Map || !listHas(session['steps'], 4)) return false;
      return value['practiceMode']?.toString() == practiceMode &&
          session['mode']?.toString() == practiceMode &&
          session['level']?.toString().toUpperCase() == normalizedLevel &&
          nonEmpty(session['grammar_focus']);
    }

    bool vocabularySafe() {
      final entries = value['entries'];
      if (!listHas(entries, 5)) return false;
      final examples = value['storyExamples'];
      if (examples is! Map) return false;
      return (entries as List).every(
        (entry) =>
            entry is Map &&
            nonEmpty(entry['id']) &&
            nonEmpty(entry['en']) &&
            safeFrench(
              entry['fr'],
              maxWords: normalizedLevel == 'A1' ? 3 : null,
            ) &&
            notEchoedEnglish(entry['fr'], entry['en']) &&
            examples[entry['id']] is Map &&
            nonEmpty((examples[entry['id']] as Map)['fr']) &&
            nonEmpty((examples[entry['id']] as Map)['en']) &&
            notEchoedEnglish(
              (examples[entry['id']] as Map)['fr'],
              (examples[entry['id']] as Map)['en'],
            ),
      );
    }

    return switch (primarySkill) {
      SpeakSkill.listening =>
        storyHasSegments() &&
            nonEmpty(value['audioPath']) &&
            nonEmpty(value['audioMode']),
      SpeakSkill.reading => storyHasSegments(),
      SpeakSkill.speaking ||
      SpeakSkill.roleplay ||
      SpeakSkill.freeTalk => speakingLinesSafe(),
      SpeakSkill.writing => writingCourseSafe(),
      SpeakSkill.vocabulary => vocabularySafe(),
      SpeakSkill.grammar => grammarCourseSafe(),
      SpeakSkill.alphabet ||
      SpeakSkill.connectors ||
      SpeakSkill.liaison ||
      SpeakSkill.review => true,
    };
  }

  /// Foundation is block zero. Every personalized group of five is one frozen
  /// adaptive batch after it.
  int get blockIndex => isFoundation
      ? 0
      : ((sequence - adaptiveCourseFoundationSize - 1) ~/
                adaptiveCourseBatchSize) +
            1;

  int get blockPosition => isFoundation
      ? sequence
      : ((sequence - adaptiveCourseFoundationSize - 1) %
                adaptiveCourseBatchSize) +
            1;

  String get targetPhrasePrompt => targetPhrases.isEmpty
      ? 'Choose from the competency.'
      : targetPhrases.join('; ');

  String get learningMix =>
      'Reuse recent learner language for about 60% of the session and add about 40% new language.';

  /// The exact existing Practice engine this course row must open. A CEFR
  /// band can simplify its content, but it must never substitute another
  /// interaction (for example Writing word-picking inside Speaking).
  String get practiceMode => switch (primarySkill) {
    SpeakSkill.speaking ||
    SpeakSkill.roleplay ||
    SpeakSkill.freeTalk => 'guidedConversation',
    SpeakSkill.writing => switch ((sequence - 6) % 3) {
      1 => 'complete',
      2 => 'roleplay',
      _ => 'guided',
    },
    SpeakSkill.grammar => switch ((sequence - 6) % 3) {
      1 => 'complete',
      2 => 'roleplay',
      _ => 'guided',
    },
    SpeakSkill.listening => switch ((sequence - 6) % 3) {
      1 => 'narration',
      2 => 'music',
      _ => 'story',
    },
    SpeakSkill.reading => 'story',
    SpeakSkill.vocabulary => 'wordsAndSentences',
    SpeakSkill.alphabet => 'alphabet',
    SpeakSkill.connectors => 'connectors',
    SpeakSkill.liaison => 'wordPairs',
    SpeakSkill.review => 'review',
  };

  /// The learner-facing phase of the shared course route. Keeping this on the
  /// stable session specification lets Course, Home, Practice, and Speaking
  /// describe the same progression without each screen inventing its own
  /// lesson order.
  String get learningPhase {
    if (sequence <= adaptiveCourseFoundationSize) {
      return switch (sequence) {
        1 => 'Sound foundation: recognize the French alphabet.',
        2 => 'Sound foundation: hear and produce French vowels.',
        3 => 'Sound foundation: hear and produce French consonants.',
        4 => 'Sound foundation: notice accents and spelling clues.',
        _ => 'A1 guided speaking: introduce yourself with confidence.',
      };
    }
    return switch (primarySkill) {
      SpeakSkill.vocabulary => 'Discover five connected words in context.',
      SpeakSkill.reading => 'Read the language in a short, useful context.',
      SpeakSkill.listening =>
        'Listen for meaning and details in connected speech.',
      SpeakSkill.writing => 'Build a clear written response in context.',
      SpeakSkill.grammar => 'Notice and use one useful sentence pattern.',
      _ => 'Speak and reuse the unit language in a short exchange.',
    };
  }

  String get contextPrompt =>
      '''PERSONALIZED COURSE SESSION
Goal: ${subtitle.split(' · ').first}
CEFR level: $level
Competency: $competency
Situation: $context
Primary skill: ${primarySkill.label}
Exact Practice mode: $practiceMode
Supporting skills: ${supportingSkills.map((skill) => skill.label).join(', ')}
Learning phase: $learningPhase
Learning mix: $learningMix
Target phrases: $targetPhrasePrompt
Grammar focus: ${grammarFocus.isEmpty ? 'Choose only what supports the competency.' : grammarFocus.join(', ')}
Session length: $estimatedMinutes minutes

SUCCESS CRITERIA
${successCriteria.map((criterion) => '- $criterion').join('\n')}

GENERATION RULES
- Teach this competency in the learner's chosen situation, not a generic travel or café lesson.
- Keep French at exactly $level, even when the context is professional or exam-oriented.
- This is lesson $sequence. ${sequence <= adaptiveCourseSimplePhaseEnd ? 'It is in the early guided phase: use the matching simple Practice mode before asking for open production.' : 'The learner may now receive a wider version of the same Practice mode.'}
- The first 60% of a batch should retrieve onboarding focus and recent learner language; use the remaining 40% for one small, level-appropriate extension.
- Use a compact lesson structure: a short heading, a one-line subtitle, two to four concrete French examples, one controlled check, and one transfer prompt.
- Explain one idea at a time in one or two short sentences. Never place a long plan, goal, audience, or context paragraph in a heading.
- Show examples before asking the learner to produce language; keep each example short enough to scan on a phone.
- Keep stories, quizzes, vocabulary, roleplays, writing tasks, speaking prompts, and cover art coherent with this situation.
- Reuse the target phrases across more than one activity, then add one small new challenge.
- Follow the learning mix above. Repetition must be retrieval and use, not a copied explanation or identical question.
- Do not repeat a previous scene or invent unrelated topics.
''';

  AdaptiveCourseSessionSpec copyWith({
    String? planId,
    String? profileFingerprint,
    String? status,
    DateTime? completedAt,
    List<String>? targetPhrases,
    List<String>? sourceSessionIds,
    String? generationStatus,
    String? artifactKind,
    Map<String, dynamic>? artifact,
    int? generationVersion,
    int? generationAttempts,
    String? generationError,
  }) {
    return AdaptiveCourseSessionSpec(
      id: id,
      planId: planId ?? this.planId,
      contentKey: contentKey,
      sequence: sequence,
      level: level,
      unit: unit,
      unitTitle: unitTitle,
      title: title,
      subtitle: subtitle,
      competency: competency,
      context: context,
      primarySkill: primarySkill,
      supportingSkills: supportingSkills,
      grammarFocus: grammarFocus,
      successCriteria: successCriteria,
      estimatedMinutes: estimatedMinutes,
      targetPhrases: targetPhrases ?? this.targetPhrases,
      sourceSessionIds: sourceSessionIds ?? this.sourceSessionIds,
      generationStatus: generationStatus ?? this.generationStatus,
      artifactKind: artifactKind ?? this.artifactKind,
      artifact: artifact ?? this.artifact,
      generationVersion: generationVersion ?? this.generationVersion,
      generationAttempts: generationAttempts ?? this.generationAttempts,
      generationError: generationError ?? this.generationError,
      profileFingerprint: profileFingerprint ?? this.profileFingerprint,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class AdaptiveCoursePlanSnapshot {
  const AdaptiveCoursePlanSnapshot({
    required this.id,
    required this.goal,
    required this.level,
    required this.profileFingerprint,
    required this.version,
    required this.sessions,
    this.status = 'active',
  });

  final String id;
  final String goal;
  final String level;
  final String profileFingerprint;
  final int version;
  final List<AdaptiveCourseSessionSpec> sessions;
  final String status;

  AdaptiveCourseSessionSpec? get nextSession =>
      sessions.cast<AdaptiveCourseSessionSpec?>().firstWhere(
        (session) => session != null && session.status != 'completed',
        orElse: () => null,
      );
}

/// Persists the adaptive route separately from the legacy bundled catalog.
///
/// The store keeps the five fixed foundation lessons plus a small personalized
/// queue. Personalized rows are appended one at a time after the learner
/// finishes the current row, up to five total Unit 2+ lessons. A profile
/// change replaces only unfinished future sessions and preserves completed
/// work.
class AdaptiveCourseStore {
  AdaptiveCourseStore(this._db, {this._onPlanChanged, this._onSessionChanged}) {
    runAppMigrations(_db);
    _ensureLearningEvidenceColumns();
  }

  final CommonDatabase _db;
  final Future<void> Function(AdaptiveCoursePlanSnapshot plan)? _onPlanChanged;
  final Future<void> Function(AdaptiveCourseSessionSpec session)?
  _onSessionChanged;

  // Foundation (1-5) and Unit 2 (6-10) are both authored, not AI-generated,
  // so there is no cost reason to reveal them one row at a time. A learner
  // should see the whole free structure — vocabulary, speaking, reading,
  // listening, writing — the moment their plan is created, the same way
  // foundation has always been fully visible immediately. Only sequence 11+
  // (real AI generation) grows one row at a time.
  static const initialBatchSize =
      adaptiveCourseFoundationSize + adaptiveCourseBatchSize;
  static const maxPersonalizedLessons = adaptiveCourseBatchSize;

  /// Older local databases may have been opened before the adaptive target
  /// columns existed. Keep this additive compatibility check next to the
  /// store so Course remains readable while the Supabase migration rolls out.
  void _ensureLearningEvidenceColumns() {
    final columns = _db.select('PRAGMA table_info(adaptive_course_sessions)');
    if (columns.isEmpty) return;
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('target_phrases_json')) {
      _db.execute(
        "ALTER TABLE adaptive_course_sessions ADD COLUMN target_phrases_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (!names.contains('source_session_ids_json')) {
      _db.execute(
        "ALTER TABLE adaptive_course_sessions ADD COLUMN source_session_ids_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
  }

  AdaptiveCoursePlanSnapshot ensureCurrentPlan(Profile profile) {
    final snapshot = UniversalLearningDataService.buildSnapshot(_db, profile);
    final fingerprint = adaptiveProfileFingerprint(profile, snapshot: snapshot);
    final active = _activePlanRow();
    if (active != null && active['profile_fingerprint'] == fingerprint) {
      final plan = _snapshotFromPlanRow(active);
      final repaired = _repairSequenceGaps(
        planId: plan.id,
        profile: profile,
        profileFingerprint: fingerprint,
        minimumSequence: initialBatchSize,
        snapshot: snapshot,
      );
      _reconcileCompletedSessions(plan.id);
      final reconciled = _snapshotForPlan(plan.id);
      if (repaired) _notifyPlan(reconciled);
      // Growth only ever looks at real AI-generated lessons (sequence 11+).
      // Unit 2 (6-10) is fixed, authored content for every learner, never
      // part of this accounting.
      //
      // The only "one at a time" rule that matters is technical: never let
      // two generations run at once. There is no cap on how many may sit
      // ready ahead, and growth is never gated on completion — opening a
      // lesson (even without finishing it, even out of order) counts as
      // "reached" it. The route simply keeps a rolling lookahead buffer
      // beyond wherever the learner has reached, refilled one lesson at a
      // time, forever, so speeding ahead or jumping around never runs out
      // of fresh content.
      final personalized = reconciled.sessions
          .where((session) => session.sequence > initialBatchSize)
          .toList(growable: false);
      final isGenerating = personalized.any(
        (session) => session.generationStatus == 'generating',
      );
      var highestReached = initialBatchSize;
      var highestExisting = initialBatchSize;
      for (final session in personalized) {
        if (session.sequence > highestExisting) {
          highestExisting = session.sequence;
        }
        if (session.status != 'planned' && session.sequence > highestReached) {
          highestReached = session.sequence;
        }
      }
      if (!isGenerating &&
          highestExisting < highestReached + adaptiveCourseLookahead) {
        _appendBatch(
          planId: reconciled.id,
          profile: profile,
          profileFingerprint: fingerprint,
          startSequence: _nextSequence(reconciled.sessions),
          batchSize: 1,
          snapshot: snapshot,
        );
        final expanded = _snapshotForPlan(reconciled.id);
        _notifyPlan(expanded);
        return expanded;
      }
      return reconciled;
    }

    return _createPlan(
      profile: profile,
      profileFingerprint: fingerprint,
      previousPlanId: active?['id']?.toString(),
      nextVersion: ((active?['version'] as int?) ?? 0) + 1,
      snapshot: snapshot,
    );
  }

  AdaptiveCoursePlanSnapshot? currentPlan(Profile profile) {
    final snapshot = UniversalLearningDataService.buildSnapshot(_db, profile);
    final fingerprint = adaptiveProfileFingerprint(profile, snapshot: snapshot);
    final row = _activePlanRow();
    if (row == null || row['profile_fingerprint'] != fingerprint) return null;
    return _snapshotFromPlanRow(row);
  }

  AdaptiveCoursePlanSnapshot? planById(String planId) {
    final rows = _db.select(
      'SELECT * FROM adaptive_course_plans WHERE id = ? AND deleted_at IS NULL',
      [planId],
    );
    if (rows.isEmpty) return null;
    return _snapshotFromPlanRow(Map<String, dynamic>.from(rows.first));
  }

  AdaptiveCourseSessionSpec? sessionById(String sessionId) {
    final rows = _db.select(
      'SELECT * FROM adaptive_course_sessions WHERE id = ? AND deleted_at IS NULL',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(Map<String, dynamic>.from(rows.first));
  }

  /// Associates the pre-auth onboarding route with the authenticated account
  /// without changing its stable ids. Onboarding intentionally runs before
  /// sign-in, so this adoption step lets a new account upload the route that
  /// was already prepared on the device.
  void linkSupabaseUser(String userId) {
    _db.execute(
      'UPDATE adaptive_course_plans SET user_id = ?, updated_at = ? '
      'WHERE user_id IS NULL AND deleted_at IS NULL',
      [userId, _now()],
    );
    _db.execute(
      'UPDATE adaptive_course_sessions SET user_id = ?, updated_at = ? '
      'WHERE user_id IS NULL AND deleted_at IS NULL',
      [userId, _now()],
    );
  }

  /// If the server already has a route, a newly installed device may have
  /// generated a temporary pre-auth route during onboarding. Archive those
  /// duplicate local routes so the hydrated server route is resumed. If the
  /// server has no plans, this is deliberately skipped and the local route is
  /// uploaded instead.
  void archivePlansNotIn(String userId, Set<String> remotePlanIds) {
    if (remotePlanIds.isEmpty) return;
    final placeholders = List.filled(remotePlanIds.length, '?').join(', ');
    _db.execute(
      "UPDATE adaptive_course_plans SET status = 'replaced', updated_at = ? "
      'WHERE user_id = ? AND status = \'active\' AND deleted_at IS NULL '
      'AND id NOT IN ($placeholders)',
      [_now(), userId, ...remotePlanIds],
    );
  }

  void markStarted(String contentKey) {
    final plan = _activePlanRow();
    if (plan == null) return;
    final planId = plan['id'] as String;
    final now = _now();
    // Only one session should ever be "the one the learner just opened" at
    // a time. This never demoted the previous holder, so every lesson ever
    // opened stayed 'active' forever — three or more rows could show as
    // active at once, purely from having opened three lessons across
    // different visits.
    _db.execute(
      "UPDATE adaptive_course_sessions SET status = 'planned', updated_at = ? "
      "WHERE plan_id = ? AND content_key != ? AND status = 'active' AND deleted_at IS NULL",
      [now, planId, contentKey],
    );
    _db.execute(
      "UPDATE adaptive_course_sessions SET status = 'active', updated_at = ? "
      "WHERE plan_id = ? AND content_key = ? AND status = 'planned' AND deleted_at IS NULL",
      [now, planId, contentKey],
    );
    final session = _sessionByContentKey(planId, contentKey);
    if (session != null) _notifySession(session);
  }

  void markCompleted(String contentKey) {
    final plan = _activePlanRow();
    if (plan == null) return;
    final now = _now();
    _db.execute(
      "UPDATE adaptive_course_sessions SET status = 'completed', completed_at = ?, updated_at = ? "
      "WHERE plan_id = ? AND content_key = ? AND deleted_at IS NULL",
      [now, now, plan['id'], contentKey],
    );
    final session = _sessionByContentKey(plan['id'] as String, contentKey);
    if (session != null) _notifySession(session);
  }

  static String adaptiveProfileFingerprint(
    Profile profile, {
    UniversalLearningSnapshot? snapshot,
  }) {
    final interests =
        profile.interests
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toList()
          ..sort();
    final profileFingerprint = [
      profile.goal.trim().toLowerCase(),
      SpeakCurriculumLevel.normalise(profile.level),
      profile.sessionLength,
      interests.join(','),
    ].join('|');
    // Learning evidence shapes a newly appended five-lesson batch, but it is
    // not plan identity. Otherwise every transcript or practice event can
    // replace unfinished lessons and create duplicate remote plans.
    return profileFingerprint;
  }

  AdaptiveCoursePlanSnapshot _createPlan({
    required Profile profile,
    required String profileFingerprint,
    required String? previousPlanId,
    required int nextVersion,
    required UniversalLearningSnapshot snapshot,
  }) {
    final planId = _adaptiveUuid.v4();
    final now = _now();
    _db.execute(
      "UPDATE adaptive_course_plans SET status = 'replaced', updated_at = ? "
      "WHERE status = 'active' AND deleted_at IS NULL AND user_id IS ?",
      [now, _localUserId()],
    );
    if (previousPlanId != null) {
      final replaced = planById(previousPlanId);
      if (replaced != null) _notifyPlan(replaced);
    }
    _db.execute(
      '''INSERT INTO adaptive_course_plans
         (id, user_id, goal, level, profile_fingerprint, version, status,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)''',
      [
        planId,
        _localUserId(),
        profile.goal,
        SpeakCurriculumLevel.normalise(profile.level),
        profileFingerprint,
        nextVersion,
        now,
        now,
      ],
    );

    if (previousPlanId != null) {
      final completed = _sessionsForPlan(
        previousPlanId,
      ).where((session) => session.status == 'completed').toList();
      completed.sort((a, b) => a.sequence.compareTo(b.sequence));
      for (final session in completed) {
        _insertSession(
          session.copyWith(
            planId: planId,
            profileFingerprint: profileFingerprint,
          ),
          planId: planId,
          profileFingerprint: profileFingerprint,
          id: _adaptiveUuid.v4(),
        );
      }
    }

    // A profile change keeps completed lessons, but must still rebuild every
    // missing earlier slot around them. This prevents a new plan from
    // starting at Unit 4 just because the learner previously completed a
    // later session.
    _repairSequenceGaps(
      planId: planId,
      profile: profile,
      profileFingerprint: profileFingerprint,
      minimumSequence: initialBatchSize,
      snapshot: snapshot,
    );
    final repaired = _snapshotForPlan(planId);
    _appendBatch(
      planId: planId,
      profile: profile,
      profileFingerprint: profileFingerprint,
      startSequence: _nextSequence(repaired.sessions),
      batchSize: initialBatchSize,
      snapshot: snapshot,
    );
    final planSnapshot = _snapshotForPlan(planId);
    _notifyPlan(planSnapshot);
    return planSnapshot;
  }

  /// Reconnects a locally rebuilt plan to course completions restored through
  /// the existing `sessions` sync table. Matching is intentionally by exact
  /// content key; matching by count could mark a different lesson complete
  /// when Unit 1/2 rows were missing during hydration.
  void _reconcileCompletedSessions(String planId) {
    final externalRows = _db.select(
      "SELECT DISTINCT content_key FROM sessions "
      "WHERE content_key LIKE 'adaptive_%' AND deleted_at IS NULL "
      'AND user_id IS ?',
      [_localUserId()],
    );
    if (externalRows.isEmpty) return;
    final now = _now();
    for (final row in externalRows) {
      final contentKey = row['content_key']?.toString();
      if (contentKey == null || contentKey.isEmpty) continue;
      _db.execute(
        "UPDATE adaptive_course_sessions SET status = 'completed', completed_at = ?, updated_at = ? "
        "WHERE plan_id = ? AND content_key = ? AND status != 'completed' "
        'AND deleted_at IS NULL',
        [now, now, planId, contentKey],
      );
    }
  }

  /// Repairs a partially hydrated or older plan without replacing its ids or
  /// completion state. A new route starts with the five foundations and one
  /// personalized row; later gaps are repaired up to the highest known sequence.
  /// This makes Unit 1 and Unit 2 durable even when Supabase previously
  /// returned only later rows.
  bool _repairSequenceGaps({
    required String planId,
    required Profile profile,
    required String profileFingerprint,
    required int minimumSequence,
    required UniversalLearningSnapshot snapshot,
  }) {
    final existing = _sessionsForPlan(planId);
    if (existing.isEmpty) return false;
    final highest = existing
        .map((session) => session.sequence)
        .reduce((a, b) => a > b ? a : b);
    // Course's personalized route is unlimited: repair only ever rebuilds
    // up to the highest sequence that already exists (never invents rows
    // ahead of what the learner's route has actually grown to).
    final target = highest > minimumSequence ? highest : minimumSequence;
    final existingBySequence = <int, AdaptiveCourseSessionSpec>{
      for (final session in existing) session.sequence: session,
    };
    final generated = AdaptiveCoursePlanGenerator.generate(
      profile: profile,
      planId: planId,
      profileFingerprint: profileFingerprint,
      startSequence: 1,
      count: target,
      learningSnapshot: snapshot,
    );
    var repaired = false;
    for (final session in generated) {
      final current = existingBySequence[session.sequence];
      if (current == null) {
        _insertSession(
          session,
          planId: planId,
          profileFingerprint: profileFingerprint,
        );
        repaired = true;
        continue;
      }

      // Upgrade unfinished rows in place so an existing installation gets
      // the staged CEFR curriculum without losing its stable id, status, or
      // progress key. Completed rows remain historical records. The early
      // personalized phase is included because older installs may already
      // have persisted an advanced template for lesson 6–15.
      final needsArtifactContractUpgrade =
          current.generationVersion < session.generationVersion;
      final isAuthoredIntroduction = session.sequence == 5;
      if ((session.sequence <= adaptiveCourseSimplePhaseEnd ||
              needsArtifactContractUpgrade) &&
          current.status != 'replaced' &&
          (isAuthoredIntroduction || current.status != 'completed') &&
          _needsCurriculumUpgrade(current, session, profileFingerprint)) {
        _updatePlannedSessionSpec(
          current,
          session,
          profileFingerprint: profileFingerprint,
          allowCompletedIntroduction: isAuthoredIntroduction,
        );
        repaired = true;
      }
    }
    if (repaired) {
      _db.execute(
        'UPDATE adaptive_course_plans SET updated_at = ? WHERE id = ?',
        [_now(), planId],
      );
    }
    return repaired;
  }

  bool _needsCurriculumUpgrade(
    AdaptiveCourseSessionSpec current,
    AdaptiveCourseSessionSpec replacement,
    String profileFingerprint,
  ) {
    final structuralChange =
        current.contentKey != replacement.contentKey ||
        current.level != replacement.level ||
        current.unit != replacement.unit ||
        current.unitTitle != replacement.unitTitle ||
        current.title != replacement.title ||
        current.subtitle != replacement.subtitle ||
        current.primarySkill != replacement.primarySkill ||
        current.supportingSkills.map((skill) => skill.wireName).join('|') !=
            replacement.supportingSkills
                .map((skill) => skill.wireName)
                .join('|') ||
        current.grammarFocus.join('|') != replacement.grammarFocus.join('|') ||
        current.successCriteria.join('|') !=
            replacement.successCriteria.join('|') ||
        current.estimatedMinutes != replacement.estimatedMinutes ||
        current.profileFingerprint != profileFingerprint ||
        current.generationVersion < replacement.generationVersion;
    if (structuralChange) return true;
    // A real, repeatedly reported bug: competency/context/targetPhrases/
    // sourceSessionIds are all rebuilt from "recent evidence" (the
    // learner's latest transcripts, completions, vocabulary results),
    // which legitimately changes every time the learner does anything else
    // in the app. Comparing an already-generated lesson's stored (historical)
    // values against a freshly recomputed replacement meant almost any
    // Course open would see a "difference" and reset a already-'ready'
    // lesson back to queued/no-artifact -- discarding real generated
    // content the learner had already reached, over and over. Once a
    // session has been generated (or is actively generating), the evidence
    // that shaped it is history, not staleness; only a genuine structural
    // change (checked above) or a real content-contract version bump
    // justifies touching it again.
    if (current.generationStatus != 'queued' || current.artifact != null) {
      return false;
    }
    return current.competency != replacement.competency ||
        current.context != replacement.context ||
        current.targetPhrases.join('|') !=
            replacement.targetPhrases.join('|') ||
        current.sourceSessionIds.join('|') !=
            replacement.sourceSessionIds.join('|');
  }

  void _updatePlannedSessionSpec(
    AdaptiveCourseSessionSpec current,
    AdaptiveCourseSessionSpec replacement, {
    required String profileFingerprint,
    bool allowCompletedIntroduction = false,
  }) {
    // Unit 2 is authored, not generated (see `_unitTwoArtifact`): its
    // recomputed `replacement` already carries the exact ready artifact
    // every time, deterministically. A repair pass must apply that fresh
    // authored content directly, never fall back to the ordinary
    // "personalized rows always start queued" reset — that would throw away
    // instantly-ready content for no reason.
    final isAuthored = replacement.artifact != null;
    final shouldResetPersonalized =
        replacement.sequence > adaptiveCourseFoundationSize && !isAuthored;
    _db.execute(
      '''UPDATE adaptive_course_sessions
         SET content_key = ?, level = ?, unit = ?, unit_title = ?, title = ?, subtitle = ?,
             competency = ?, context = ?, primary_skill = ?,
             supporting_skills_json = ?, grammar_focus_json = ?,
             success_criteria_json = ?, estimated_minutes = ?,
             target_phrases_json = ?, source_session_ids_json = ?,
             profile_fingerprint = ?, generation_version = ?,
             generation_status = CASE WHEN ? = 1 THEN 'queued' WHEN ? = 1 THEN ? ELSE generation_status END,
             artifact_kind = CASE WHEN ? = 1 THEN NULL WHEN ? = 1 THEN ? ELSE artifact_kind END,
             artifact_json = CASE WHEN ? = 1 THEN NULL WHEN ? = 1 THEN ? ELSE artifact_json END,
             generation_error = CASE WHEN ? = 1 THEN 'Regenerating with CEFR and early-phase rules' WHEN ? = 1 THEN NULL ELSE generation_error END,
             updated_at = ?
         WHERE id = ?
           AND (? = 1 OR status NOT IN ('completed', 'replaced'))
           AND deleted_at IS NULL''',
      [
        replacement.contentKey,
        replacement.level,
        replacement.unit,
        replacement.unitTitle,
        replacement.title,
        replacement.subtitle,
        replacement.competency,
        replacement.context,
        replacement.primarySkill.wireName,
        jsonEncode(
          replacement.supportingSkills.map((skill) => skill.wireName).toList(),
        ),
        jsonEncode(replacement.grammarFocus),
        jsonEncode(replacement.successCriteria),
        replacement.estimatedMinutes,
        jsonEncode(replacement.targetPhrases),
        jsonEncode(replacement.sourceSessionIds),
        profileFingerprint,
        replacement.generationVersion,
        shouldResetPersonalized ? 1 : 0,
        isAuthored ? 1 : 0,
        replacement.generationStatus,
        shouldResetPersonalized ? 1 : 0,
        isAuthored ? 1 : 0,
        replacement.artifactKind,
        shouldResetPersonalized ? 1 : 0,
        isAuthored ? 1 : 0,
        replacement.artifact == null ? null : jsonEncode(replacement.artifact),
        shouldResetPersonalized ? 1 : 0,
        isAuthored ? 1 : 0,
        _now(),
        current.id,
        allowCompletedIntroduction ? 1 : 0,
      ],
    );
    // Session 5 used to be a generated vocabulary row. When an existing
    // installation is upgraded, remove that obsolete payload so the
    // canonical authored speaking lesson is the only content that can open.
    if (replacement.sequence == adaptiveCourseFoundationSize) {
      _db.execute(
        '''UPDATE adaptive_course_sessions
           SET generation_status = 'ready', artifact_kind = NULL,
               artifact_json = NULL, generation_attempts = 0,
               generation_error = NULL, updated_at = ?
           WHERE id = ? AND deleted_at IS NULL''',
        [_now(), current.id],
      );
    }
  }

  void _appendBatch({
    required String planId,
    required Profile profile,
    required String profileFingerprint,
    required int startSequence,
    required int batchSize,
    required UniversalLearningSnapshot snapshot,
  }) {
    final existingSequences = _sessionsForPlan(
      planId,
    ).map((s) => s.sequence).toSet();
    final generated = AdaptiveCoursePlanGenerator.generate(
      profile: profile,
      planId: planId,
      profileFingerprint: profileFingerprint,
      startSequence: startSequence,
      count: batchSize,
      learningSnapshot: snapshot,
    );
    for (final session in generated) {
      if (!existingSequences.contains(session.sequence)) {
        _insertSession(
          session,
          planId: planId,
          profileFingerprint: profileFingerprint,
        );
      }
    }
    _db.execute(
      'UPDATE adaptive_course_plans SET updated_at = ? WHERE id = ?',
      [_now(), planId],
    );
  }

  int _nextSequence(List<AdaptiveCourseSessionSpec> sessions) {
    if (sessions.isEmpty) return 1;
    return sessions
            .map((session) => session.sequence)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  Map<String, dynamic>? _activePlanRow() {
    final userId = _localUserId();
    final rows = _db.select(
      "SELECT * FROM adaptive_course_plans WHERE status = 'active' AND deleted_at IS NULL "
      'AND user_id IS ? ORDER BY version DESC, created_at DESC LIMIT 1',
      [userId],
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  String? _localUserId() {
    final rows = _db.select(
      'SELECT user_id FROM profiles WHERE deleted_at IS NULL LIMIT 1',
    );
    return rows.isEmpty ? null : rows.first['user_id'] as String?;
  }

  AdaptiveCoursePlanSnapshot _snapshotForPlan(String planId) {
    final rows = _db.select(
      'SELECT * FROM adaptive_course_plans WHERE id = ? AND deleted_at IS NULL',
      [planId],
    );
    return _snapshotFromPlanRow(Map<String, dynamic>.from(rows.first));
  }

  AdaptiveCoursePlanSnapshot _snapshotFromPlanRow(Map<String, dynamic> row) {
    return AdaptiveCoursePlanSnapshot(
      id: row['id'] as String,
      goal: row['goal'] as String,
      level: row['level'] as String,
      profileFingerprint: row['profile_fingerprint'] as String,
      version: row['version'] as int,
      sessions: _sessionsForPlan(row['id'] as String),
      status: row['status'] as String? ?? 'active',
    );
  }

  List<AdaptiveCourseSessionSpec> _sessionsForPlan(String planId) {
    final rows = _db.select(
      'SELECT * FROM adaptive_course_sessions WHERE plan_id = ? AND deleted_at IS NULL ORDER BY sequence',
      [planId],
    );
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  void _insertSession(
    AdaptiveCourseSessionSpec session, {
    required String planId,
    required String profileFingerprint,
    String? id,
  }) {
    final now = _now();
    _db.execute(
      '''INSERT INTO adaptive_course_sessions
        (id, plan_id, content_key, sequence, level, unit, unit_title, title,
         subtitle, competency, context, primary_skill, supporting_skills_json,
         grammar_focus_json, success_criteria_json, estimated_minutes,
         target_phrases_json, source_session_ids_json, profile_fingerprint,
         generation_status, artifact_kind, artifact_json, generation_version,
         generation_attempts, generation_error, status, created_at, updated_at,
         completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id ?? session.id,
        planId,
        session.contentKey,
        session.sequence,
        session.level,
        session.unit,
        session.unitTitle,
        session.title,
        session.subtitle,
        session.competency,
        session.context,
        session.primarySkill.wireName,
        jsonEncode(
          session.supportingSkills.map((skill) => skill.wireName).toList(),
        ),
        jsonEncode(session.grammarFocus),
        jsonEncode(session.successCriteria),
        session.estimatedMinutes,
        jsonEncode(session.targetPhrases),
        jsonEncode(session.sourceSessionIds),
        profileFingerprint,
        session.generationStatus,
        session.artifactKind,
        session.artifact == null ? null : jsonEncode(session.artifact),
        session.generationVersion,
        session.generationAttempts,
        session.generationError,
        session.status,
        session.createdAt.toUtc().toIso8601String(),
        now,
        session.completedAt?.toUtc().toIso8601String(),
      ],
    );
  }

  AdaptiveCourseSessionSpec _sessionFromRow(Map<String, dynamic> row) {
    List<dynamic> decodeList(Object? value) {
      if (value is List) return value;
      return jsonDecode(value?.toString() ?? '[]') as List;
    }

    return AdaptiveCourseSessionSpec(
      id: row['id'] as String,
      planId: row['plan_id'] as String,
      contentKey: row['content_key'] as String,
      sequence: row['sequence'] as int,
      level: row['level'] as String,
      unit: row['unit'] as int,
      unitTitle: row['unit_title'] as String,
      title: row['title'] as String,
      subtitle: row['subtitle'] as String,
      competency: row['competency'] as String,
      context: row['context'] as String,
      primarySkill:
          speakSkillFromWire(row['primary_skill']) ?? SpeakSkill.speaking,
      supportingSkills: decodeList(
        row['supporting_skills_json'],
      ).map(speakSkillFromWire).whereType<SpeakSkill>().toList(growable: false),
      grammarFocus: decodeList(
        row['grammar_focus_json'],
      ).map((e) => e.toString()).toList(growable: false),
      successCriteria: decodeList(
        row['success_criteria_json'],
      ).map((e) => e.toString()).toList(growable: false),
      estimatedMinutes: row['estimated_minutes'] as int,
      targetPhrases: decodeList(
        row['target_phrases_json'],
      ).map((e) => e.toString()).toList(growable: false),
      sourceSessionIds: decodeList(
        row['source_session_ids_json'],
      ).map((e) => e.toString()).toList(growable: false),
      generationStatus:
          row['generation_status']?.toString() ??
          ((row['sequence'] as int) <= adaptiveCourseFoundationSize
              ? 'ready'
              : 'queued'),
      artifactKind: row['artifact_kind']?.toString(),
      artifact: _decodeMap(row['artifact_json']),
      generationVersion: (row['generation_version'] as int?) ?? 1,
      generationAttempts: (row['generation_attempts'] as int?) ?? 0,
      generationError: row['generation_error']?.toString(),
      profileFingerprint: row['profile_fingerprint'] as String,
      status: row['status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.tryParse(row['completed_at'] as String),
    );
  }

  AdaptiveCourseSessionSpec? _sessionByContentKey(
    String planId,
    String contentKey,
  ) {
    final rows = _db.select(
      'SELECT * FROM adaptive_course_sessions '
      'WHERE plan_id = ? AND content_key = ? AND deleted_at IS NULL '
      'ORDER BY sequence DESC LIMIT 1',
      [planId, contentKey],
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(Map<String, dynamic>.from(rows.first));
  }

  /// Hydrates a plan row downloaded from Supabase without creating another
  /// sync mutation. Remote rows win only when they are newer than the local
  /// cache, so an offline local edit is not overwritten before its outbox
  /// retry succeeds.
  void upsertPlanFromRemote(Map<String, dynamic> row) {
    _db.execute(
      '''INSERT INTO adaptive_course_plans
         (id, user_id, goal, level, profile_fingerprint, version, status,
          created_at, updated_at, deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           user_id = excluded.user_id,
           goal = excluded.goal,
           level = excluded.level,
           profile_fingerprint = excluded.profile_fingerprint,
           version = excluded.version,
           status = excluded.status,
           updated_at = excluded.updated_at,
           deleted_at = excluded.deleted_at
         WHERE excluded.updated_at > adaptive_course_plans.updated_at''',
      [
        row['id'],
        row['user_id'],
        row['goal'],
        row['level'],
        row['profile_fingerprint'],
        row['version'],
        row['status'],
        row['created_at'],
        row['updated_at'],
        row['deleted_at'],
      ],
    );
  }

  void upsertSessionFromRemote(Map<String, dynamic> row) {
    String jsonText(Object? value) => value is String
        ? value
        : jsonEncode(value is List ? value : const <Object?>[]);

    _db.execute(
      '''INSERT INTO adaptive_course_sessions
         (id, user_id, plan_id, content_key, sequence, level, unit, unit_title,
          title, subtitle, competency, context, primary_skill,
          supporting_skills_json, grammar_focus_json, success_criteria_json,
          estimated_minutes, target_phrases_json, source_session_ids_json,
          profile_fingerprint, generation_status, artifact_kind, artifact_json,
          generation_version, generation_attempts, generation_error, status,
          created_at, updated_at, completed_at, deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           user_id = excluded.user_id,
           plan_id = excluded.plan_id,
           content_key = excluded.content_key,
           sequence = excluded.sequence,
           level = excluded.level,
           unit = excluded.unit,
           unit_title = excluded.unit_title,
           title = excluded.title,
           subtitle = excluded.subtitle,
           competency = excluded.competency,
           context = excluded.context,
           primary_skill = excluded.primary_skill,
           supporting_skills_json = excluded.supporting_skills_json,
           grammar_focus_json = excluded.grammar_focus_json,
           success_criteria_json = excluded.success_criteria_json,
           estimated_minutes = excluded.estimated_minutes,
           target_phrases_json = excluded.target_phrases_json,
           source_session_ids_json = excluded.source_session_ids_json,
           profile_fingerprint = excluded.profile_fingerprint,
           -- A remote pull can legitimately be older than the durable local
           -- artifact (for example while the generation response is still
           -- propagating). Never let that stale queued/generating snapshot make
           -- a lesson disappear from the roadmap again.
           generation_status = CASE
             WHEN adaptive_course_sessions.artifact_json IS NOT NULL
                  AND excluded.artifact_json IS NULL
                  AND excluded.generation_status IN ('queued', 'generating')
               THEN adaptive_course_sessions.generation_status
             ELSE excluded.generation_status
           END,
           artifact_kind = CASE
             WHEN adaptive_course_sessions.artifact_json IS NOT NULL
                  AND excluded.artifact_json IS NULL
                  AND excluded.generation_status IN ('queued', 'generating')
               THEN adaptive_course_sessions.artifact_kind
             ELSE excluded.artifact_kind
           END,
           artifact_json = CASE
             WHEN adaptive_course_sessions.artifact_json IS NOT NULL
                  AND excluded.artifact_json IS NULL
                  AND excluded.generation_status IN ('queued', 'generating')
               THEN adaptive_course_sessions.artifact_json
             ELSE excluded.artifact_json
           END,
           generation_version = excluded.generation_version,
           generation_attempts = CASE
             WHEN adaptive_course_sessions.artifact_json IS NOT NULL
                  AND excluded.artifact_json IS NULL
                  AND excluded.generation_status IN ('queued', 'generating')
               THEN adaptive_course_sessions.generation_attempts
             ELSE excluded.generation_attempts
           END,
           generation_error = CASE
             WHEN adaptive_course_sessions.artifact_json IS NOT NULL
                  AND excluded.artifact_json IS NULL
                  AND excluded.generation_status IN ('queued', 'generating')
               THEN adaptive_course_sessions.generation_error
             ELSE excluded.generation_error
           END,
           status = excluded.status,
           updated_at = excluded.updated_at,
           completed_at = excluded.completed_at,
           deleted_at = excluded.deleted_at
         WHERE excluded.updated_at > adaptive_course_sessions.updated_at''',
      [
        row['id'],
        row['user_id'],
        row['plan_id'],
        row['content_key'],
        row['sequence'],
        row['level'],
        row['unit'],
        row['unit_title'],
        row['title'],
        row['subtitle'],
        row['competency'],
        row['context'],
        row['primary_skill'],
        jsonText(row['supporting_skills_json']),
        jsonText(row['grammar_focus_json']),
        jsonText(row['success_criteria_json']),
        row['estimated_minutes'],
        jsonText(row['target_phrases_json']),
        jsonText(row['source_session_ids_json']),
        row['profile_fingerprint'],
        row['generation_status'] ??
            (((row['sequence'] as int?) ?? 0) <= adaptiveCourseFoundationSize
                ? 'ready'
                : 'queued'),
        row['artifact_kind'],
        row['artifact_json'] == null
            ? null
            : (row['artifact_json'] is String
                  ? row['artifact_json']
                  : jsonEncode(row['artifact_json'])),
        row['generation_version'] ?? 1,
        row['generation_attempts'] ?? 0,
        row['generation_error'],
        row['status'],
        row['created_at'],
        row['updated_at'],
        row['completed_at'],
        row['deleted_at'],
      ],
    );
  }

  void _notifyPlan(AdaptiveCoursePlanSnapshot snapshot) {
    unawaited(_onPlanChanged?.call(snapshot));
  }

  void _notifySession(AdaptiveCourseSessionSpec session) {
    unawaited(_onSessionChanged?.call(session));
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}

/// Generates structured, non-repeating competency slots. The rich lesson
/// content is prepared independently and persisted before Course exposes the
/// lesson as tappable.
abstract final class AdaptiveCoursePlanGenerator {
  static List<AdaptiveCourseSessionSpec> generate({
    required Profile profile,
    required String planId,
    required String profileFingerprint,
    required int startSequence,
    required int count,
    UniversalLearningSnapshot? learningSnapshot,
  }) {
    final track = AdaptiveCurriculumService.forProfile(profile);
    // The learner's stated goal (exam prep, immigration, work...) must not
    // pick the SITUATION for the earliest A1/A2 personalized lessons, even
    // though its grammar is already kept simple. "Immigration and
    // administrative conversations" is still the wrong first scene for a
    // total beginner. Borrow the universal "everyday" track's situations for
    // this early bridge window and only switch to the learner's own track
    // once the foundation (adaptiveCourseSimplePhaseEnd) is behind them.
    final earlyBridgeTrack =
        AdaptiveCurriculumService.tracks['everyday'] ?? track;
    final level = SpeakCurriculumLevel.normalise(profile.level);
    final interest = AdaptiveCurriculumService.relevantInterest(profile);
    final recentFocusSkills =
        learningSnapshot?.recentSkills
            .where(
              (skill) => const {
                SpeakSkill.speaking,
                SpeakSkill.listening,
                SpeakSkill.reading,
                SpeakSkill.writing,
                SpeakSkill.grammar,
                SpeakSkill.vocabulary,
                SpeakSkill.review,
              }.contains(skill),
            )
            .toList(growable: false) ??
        const <SpeakSkill>[];
    final focusSkills = AdaptiveCurriculumService.focusSkills(profile);
    final templates = _templatesFor(profile.goal, level: level);
    final unitThemes = _unitThemesFor(profile.goal);
    final sessions = <AdaptiveCourseSessionSpec>[];
    // Session 5 is the permanent authored introduction. Keep the first
    // personalized batch about new competencies, and keep its titles unique.
    final usedPersonalizedTitles = <String>{
      'introduce yourself',
      'introduce yourself naturally',
    };
    for (var offset = 0; offset < count; offset++) {
      final sequence = startSequence + offset;
      final cycle = (sequence - 1) ~/ templates.length;
      final guidedPathTemplate = _guidedPathTemplate(level, sequence);
      final focusSkill = _targetSkillForBatch(
        focusSkills: focusSkills,
        recentSkills: recentFocusSkills,
        sequence: sequence,
      );
      final targetSkill = _courseSkillFor(focusSkill, sequence);
      final selectedTemplate =
          guidedPathTemplate ??
          _templateForFocus(
            templates,
            [focusSkill],
            sequence: sequence,
            cycle: cycle,
            excludedTitles: usedPersonalizedTitles,
          );
      var template = _templateForPhase(
        selectedTemplate,
        level: level,
        primarySkill: focusSkill,
        sequence: sequence,
      );
      if (sequence > adaptiveCourseFoundationSize &&
          sequence <= adaptiveCourseSimplePhaseEnd &&
          usedPersonalizedTitles.contains(template.verb.toLowerCase())) {
        for (var variantOffset = 1; variantOffset <= 3; variantOffset++) {
          final candidate = _earlyTemplateForLevel(
            level,
            focusSkill,
            sequence + variantOffset,
          );
          if (!usedPersonalizedTitles.contains(candidate.verb.toLowerCase())) {
            template = candidate;
            break;
          }
        }
      }
      if (sequence > adaptiveCourseFoundationSize) {
        usedPersonalizedTitles.add(selectedTemplate.verb.toLowerCase());
        usedPersonalizedTitles.add(template.verb.toLowerCase());
      }
      final useEarlyBridgeContext =
          sequence > adaptiveCourseFoundationSize &&
          sequence <= adaptiveCourseSimplePhaseEnd &&
          (level == 'A1' || level == 'A2');
      final contextTrack = useEarlyBridgeContext ? earlyBridgeTrack : track;
      final baseContext =
          contextTrack.contexts[(sequence - 1) % contextTrack.contexts.length];
      final foundationBase =
          'French pronunciation foundations for $baseContext';
      final foundationContext = interest == null
          ? foundationBase
          : '$foundationBase with a light connection to $interest';
      final isFoundation = sequence <= 5;
      final isGuidedIntroduction = sequence == adaptiveCourseFoundationSize;
      final context = isFoundation
          ? isGuidedIntroduction
                ? '$level guided speaking: ${SpeakingCourseCatalog.firstA1GuidedLesson.subtitle}'
                : foundationContext
          : interest == null
          ? baseContext
          : '$baseContext with a light connection to $interest';
      final personalizedContext =
          learningSnapshot?.contextForLesson(
            sequence: sequence,
            baseContext: context,
          ) ??
          context;
      final rawTargetPhrases = isGuidedIntroduction
          ? SpeakingCourseCatalog.firstA1GuidedLesson.lines
                .map((line) => line.french)
                .toList(growable: false)
          : isFoundation
          ? template.grammar
          : learningSnapshot?.targetsForLesson(
                  sequence: sequence,
                  fallback: template.grammar,
                ) ??
                template.grammar;
      final targetPhrases = _safeTargetPhrases(
        level,
        rawTargetPhrases,
        fallback: template.grammar,
      );
      final sourceSessionIds = isGuidedIntroduction
          ? const [SpeakingCourseCatalog.firstA1GuidedLessonId]
          : learningSnapshot?.sourceSessionIds
                    .take(4)
                    .toList(growable: false) ??
                const <String>[];
      final supportingSkills = <SpeakSkill>[...template.supporting];
      for (final practicedSkill
          in learningSnapshot?.recentSkills ?? const <SpeakSkill>[]) {
        if (practicedSkill != template.primary &&
            !supportingSkills.contains(practicedSkill) &&
            supportingSkills.length < 3) {
          supportingSkills.add(practicedSkill);
        }
      }
      final unit = ((sequence - 1) ~/ 5) + 1;
      final unitTheme = _unitThemeFor(unitThemes, unit);
      final title = isGuidedIntroduction
          ? SpeakingCourseCatalog.firstA1GuidedLesson.title
          : template.verb;
      final subtitle = isGuidedIntroduction
          ? '${track.label} · ${SpeakingCourseCatalog.firstA1GuidedLesson.subtitle}'
          : cycle == 0
          ? '${track.label} · ${template.competency}'
          : '${track.label} · Transfer practice · ${template.competency}';
      final isUnitTwo = _isUnitTwoSequence(sequence);
      final unitTwoArtifact = isUnitTwo
          ? _unitTwoArtifact(targetSkill, level)
          : null;
      // Unit 2 is authored, not generated: every skill including Listening
      // is ready the instant this spec exists. Listening's durable audio is
      // a single shared, publicly-readable asset (see _unitTwoArtifact) —
      // no per-learner server call, no waiting.
      final unitTwoReady = isUnitTwo;
      sessions.add(
        AdaptiveCourseSessionSpec(
          id: _adaptiveUuid.v4(),
          planId: planId,
          contentKey: isGuidedIntroduction
              ? SpeakingCourseCatalog.firstA1GuidedLessonId
              : 'adaptive_${planId}_s${sequence.toString().padLeft(3, '0')}',
          sequence: sequence,
          level: level,
          unit: unit,
          // Keep the visible roadmap title short. The track and learner
          // context remain in `subtitle`, `context`, and `contextPrompt`.
          unitTitle: unitTheme,
          title: title,
          subtitle: subtitle,
          competency: template.competency,
          context: personalizedContext,
          primarySkill: sequence <= adaptiveCourseFoundationSize
              ? template.primary
              : targetSkill,
          supportingSkills: supportingSkills,
          grammarFocus: template.grammar,
          successCriteria: template.success,
          estimatedMinutes: _minutes(profile.sessionLength, template.primary),
          targetPhrases: targetPhrases,
          sourceSessionIds: sourceSessionIds,
          generationStatus: isFoundation || unitTwoReady ? 'ready' : 'queued',
          artifactKind: unitTwoReady ? targetSkill.wireName : null,
          artifact: unitTwoArtifact,
          generationVersion: adaptiveCourseGenerationVersion,
          profileFingerprint: profileFingerprint,
          status: 'planned',
          createdAt: DateTime.now(),
        ),
      );
    }
    return sessions;
  }

  /// Only the first five sound-foundation sessions are fixed. Every session
  /// after them belongs to the sequential personalized Unit 2+ reserve.
  static _AdaptiveTemplate? _guidedPathTemplate(String level, int sequence) {
    if (sequence <= 5) {
      return _foundationTemplatesForLevel(level)[sequence - 1];
    }
    return null;
  }

  /// Unit 2 (sequences 6-10) is a second fixed, authored block, not an AI
  /// call. Every skill including Listening is ready the instant the plan is
  /// created — no network, no waiting, no possibility of a malformed
  /// generation. Listening's durable audio is a single shared, publicly
  /// readable asset (uploaded once via generate-shared-course-listening-
  /// audio-once), not a fresh per-learner render. Five words, reused across
  /// every one of the five lessons.
  static const _unitTwoWords = [
    (id: 'market', en: 'market', fr: 'marché', phonetic: 'mar-shay'),
    (id: 'apple', en: 'apple', fr: 'pomme', phonetic: 'pom'),
    (id: 'seller', en: 'seller', fr: 'vendeuse', phonetic: 'von-duhz'),
    (id: 'price', en: 'price', fr: 'prix', phonetic: 'pree'),
    (id: 'fresh', en: 'fresh', fr: 'fraîche', phonetic: 'fresh'),
  ];

  static const _unitTwoSegments = [
    (
      fr: 'Le marché est très animé.',
      en: 'The market is very lively.',
      note: 'Present tense for a current scene.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Je choisis une pomme rouge.',
      en: 'I choose a red apple.',
      note: '"Je choisis" = I choose.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'La vendeuse me sourit.',
      en: 'The seller smiles at me.',
      note: '"La vendeuse" = the (female) seller.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Nous parlons du prix.',
      en: 'We talk about the price.',
      note: '"Du prix" = about the price.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'La pomme est fraîche.',
      en: 'The apple is fresh.',
      note: '"Fraîche" agrees with a feminine noun.',
      tip: 'Listen once, then repeat naturally.',
    ),
  ];

  // Reusing the same five words across a unit is the point (spaced
  // repetition); reusing the same five SENTENCES verbatim across every
  // skill is not — that reads as duplicate content, not practice. Each
  // skill below gets its own sentences built from the same five words in a
  // different situation, so the word is genuinely being met again, not
  // re-read.
  static const _unitTwoSpeakingSegments = [
    (
      fr: 'Je vais au marché ce matin.',
      en: "I'm going to the market this morning.",
      note: '"Je vais" = I am going.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: "J'aime cette pomme verte.",
      en: 'I like this green apple.',
      note: '"J\'aime" = I like.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'La vendeuse est très gentille.',
      en: 'The seller is very kind.',
      note: '"Gentille" agrees with a feminine noun.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Quel est le prix, s\'il vous plaît ?',
      en: 'What is the price, please?',
      note: 'A short, polite question.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Cette pomme fraîche sent bon.',
      en: 'This fresh apple smells good.',
      note: '"Sent bon" = smells good.',
      tip: 'Listen once, then repeat naturally.',
    ),
  ];

  static const _unitTwoReadingSegments = [
    (
      fr: 'Ce matin, Léa va au marché avec sa mère.',
      en: 'This morning, Léa goes to the market with her mother.',
      note: 'Present tense for a habitual morning.',
      tip: 'Read once for the general idea.',
    ),
    (
      fr: 'Elles cherchent de belles pommes pour un gâteau.',
      en: 'They are looking for nice apples for a cake.',
      note: '"Cherchent" = are looking for.',
      tip: 'Read once for the general idea.',
    ),
    (
      fr: 'Une vendeuse leur montre un beau panier.',
      en: 'A seller shows them a nice basket.',
      note: '"Leur" = to them.',
      tip: 'Read once for the general idea.',
    ),
    (
      fr: 'Léa demande le prix avec un sourire.',
      en: 'Léa asks the price with a smile.',
      note: '"Demande" = asks.',
      tip: 'Read once for the general idea.',
    ),
    (
      fr: 'Chaque pomme du panier est bien fraîche.',
      en: 'Every apple in the basket is nicely fresh.',
      note: '"Chaque" = every/each.',
      tip: 'Read once for the general idea.',
    ),
  ];

  // A1 means present tense only, no superlatives, no futur simple — every
  // line here must hold up on its own as beginner French, not just carry
  // an "A1" label. (An earlier version of this set used "commence à se
  // calmer", a superlative "les plus fraîches", and futur simple
  // "commencera" — all genuinely too advanced for a true beginner.)
  static const _unitTwoListeningSegments = [
    (
      fr: 'Le soir, le marché est calme.',
      en: 'In the evening, the market is calm.',
      note: 'A new scene: closing time, not morning.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Une dernière cliente achète encore des pommes.',
      en: 'One last customer is still buying apples.',
      note: '"Encore" = still.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'La vendeuse compte le prix de chaque fruit.',
      en: 'The seller counts the price of every fruit.',
      note: '"Compte" = counts.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Elle range les pommes fraîches.',
      en: 'She puts away the fresh apples.',
      note: '"Range" = puts away.',
      tip: 'Listen once, then repeat naturally.',
    ),
    (
      fr: 'Demain, un nouveau marché ouvre tôt.',
      en: 'Tomorrow, a new market opens early.',
      note: 'Present tense with "demain" for the near future.',
      tip: 'Listen once, then repeat naturally.',
    ),
  ];

  // Writing's fill-in-the-blank needs its target word to literally appear
  // in the sentence text, so it gets its own short, plain set rather than
  // reusing another skill's sentence — same words, still a fourth distinct
  // context.
  static const _unitTwoWritingSegments = [
    (
      fr: 'Le marché ouvre tôt le samedi.',
      en: 'The market opens early on Saturday.',
    ),
    (fr: "J'achète une pomme verte.", en: "I'm buying a green apple."),
    (fr: 'La vendeuse pèse les fruits.', en: 'The seller weighs the fruit.'),
    (
      fr: "Le prix est affiché sur l'étiquette.",
      en: 'The price is shown on the label.',
    ),
    (fr: 'Cette pomme est bien fraîche.', en: 'This apple is very fresh.'),
  ];

  static bool _isUnitTwoSequence(int sequence) =>
      sequence > adaptiveCourseFoundationSize &&
      sequence <= adaptiveCourseFoundationSize + adaptiveCourseBatchSize;

  /// Builds the artifact for one Unit 2 lesson. Listening's text and its
  /// durable audio (a single shared asset, identical for every learner) are
  /// both already complete here — nothing about Unit 2 ever needs a server
  /// round trip.
  static Map<String, dynamic>? _unitTwoArtifact(
    SpeakSkill skill,
    String level,
  ) {
    switch (skill) {
      case SpeakSkill.vocabulary:
        return {
          'id': 'unit-two-vocabulary',
          'title': 'Learn common words',
          'summary': 'Five words from one French market scene.',
          'topic': 'Food & shopping',
          'levelBand': level,
          'coverUrl': 'asset:assets/starter_covers/market.png',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'entries': [
            for (final word in _unitTwoWords)
              {
                'id': word.id,
                'en': word.en,
                'fr': word.fr,
                'phonetic': word.phonetic,
              },
          ],
          'storyExamples': {
            for (var i = 0; i < _unitTwoWords.length; i++)
              _unitTwoWords[i].id: {
                'fr': _unitTwoSegments[i].fr,
                'en': _unitTwoSegments[i].en,
              },
          },
        };
      case SpeakSkill.speaking:
        return {
          'id': 'unit-two-speaking',
          'practiceMode': 'guidedConversation',
          'lines': [
            for (final segment in _unitTwoSpeakingSegments)
              {'fr': segment.fr, 'en': segment.en},
          ],
        };
      case SpeakSkill.reading:
        return {
          'id': 'unit-two-reading',
          'title': 'Le marché du matin',
          'summary': "Léa and her mother shop for apples at the market.",
          'topic': 'Food & shopping',
          'levelBand': level,
          'readTimeMinutes': 3,
          'coverUrl': 'asset:assets/starter_covers/market.png',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'passage': {
            'id': 'unit-two-reading-passage',
            'title': 'Le marché du matin',
            'titleEn': 'The morning market',
            'fullText': _unitTwoReadingSegments.map((s) => s.fr).join(' '),
            'segments': [
              for (final segment in _unitTwoReadingSegments)
                {
                  'fr': segment.fr,
                  'en': segment.en,
                  'grammarNote': segment.note,
                  'pronunciationTip': segment.tip,
                },
            ],
          },
          'quiz': [
            {
              'q': 'Pourquoi est-ce que Léa va au marché ?',
              'q_en': 'Why does Léa go to the market?',
              'choices': ['Pour un gâteau.', 'Pour dormir.', 'Pour chanter.'],
              'choices_en': ['For a cake.', 'To sleep.', 'To sing.'],
              'answerIndex': 0,
            },
          ],
          'keywords': [
            for (final word in _unitTwoWords)
              {
                'id': word.id,
                'en': word.en,
                'fr': word.fr,
                'phonetic': word.phonetic,
              },
          ],
        };
      case SpeakSkill.listening:
        return {
          'id': 'unit-two-listening',
          'title': 'Le marché ferme',
          'summary': 'The market winds down as evening comes.',
          'topic': 'Food & shopping',
          'levelBand': level,
          'readTimeMinutes': 3,
          'coverUrl': 'asset:assets/starter_covers/market.png',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'passage': {
            'id': 'unit-two-listening-passage',
            'title': 'Le marché ferme',
            'titleEn': 'The market closes',
            'fullText': _unitTwoListeningSegments.map((s) => s.fr).join(' '),
            'segments': [
              for (final segment in _unitTwoListeningSegments)
                {
                  'fr': segment.fr,
                  'en': segment.en,
                  'grammarNote': segment.note,
                  'pronunciationTip': segment.tip,
                },
            ],
          },
          'quiz': [
            {
              'q': 'Que fait la vendeuse le soir ?',
              'q_en': 'What does the seller do in the evening?',
              'choices': [
                'Elle range les pommes.',
                'Elle dort.',
                'Elle chante.',
              ],
              'choices_en': [
                'She puts away the apples.',
                'She sleeps.',
                'She sings.',
              ],
              'answerIndex': 0,
            },
          ],
          'keywords': [
            for (final word in _unitTwoWords)
              {
                'id': word.id,
                'en': word.en,
                'fr': word.fr,
                'phonetic': word.phonetic,
              },
          ],
          // Unit 2 is authored and identical for every learner. Keep the
          // shared, one-time WAV produced by the course asset generator as
          // the source of truth; the client imports it into its local
          // sentence deck without opening Gemini or generating per-user
          // copies on lesson open.
          'audioPath': 'course-shared/unit-two-listening.wav',
          'audioMode': 'gemini_flash_tts',
        };
      case SpeakSkill.writing:
        final choicesPool = _unitTwoWords.map((w) => w.fr).toList();
        Map<String, dynamic> step(int wordIndex) {
          final word = _unitTwoWords[wordIndex];
          final segment = _unitTwoWritingSegments[wordIndex];
          final blanked = segment.fr.replaceFirst(word.fr, '___');
          final distractors = choicesPool
              .where((choice) => choice != word.fr)
              .take(2)
              .toList();
          return {
            'prompt': blanked,
            'prompt_english': segment.en,
            'target': word.fr,
            'kind': 'choice',
            'choices': [word.fr, ...distractors],
            'choice_meanings': [
              word.en,
              for (final choice in distractors)
                _unitTwoWords
                    .firstWhere((candidate) => candidate.fr == choice)
                    .en,
            ],
            'tip': 'Pick the word that completes the sentence.',
          };
        }

        return {
          'id': 'unit-two-writing',
          'practiceMode': 'complete',
          'lesson': {
            'id': 'writing-unit-two',
            'title': 'Write a short reply',
            'title_en': 'Write a short reply',
            'subtitle': 'Complete each sentence with the right word.',
            'level': level,
            'mode': 'complete',
            'goal': 'Reuse this unit\'s five words in writing.',
            'steps': [for (var i = 0; i < 5; i++) step(i)],
          },
        };
      default:
        return null;
    }
  }

  /// Every personalized unit of five is taught in one fixed, slow-to-higher
  /// order: teach the words first, then reuse that same vocabulary to speak,
  /// read, listen, and finally write about it. This is deliberately not
  /// re-personalized by onboarding emphasis or recent evidence — a beginner
  /// needs the words before any of the other four activities can reuse them,
  /// and the order must stay predictable and simple across every unit.
  /// [focusSkills] and [recentSkills] are accepted for call-site compatibility
  /// but no longer change the order.
  static SpeakSkill _targetSkillForBatch({
    required List<SpeakSkill> focusSkills,
    required List<SpeakSkill> recentSkills,
    required int sequence,
  }) {
    if (sequence <= adaptiveCourseFoundationSize) return SpeakSkill.alphabet;
    final personalizedIndex = sequence - adaptiveCourseFoundationSize - 1;
    final position = personalizedIndex % adaptiveCourseBatchSize;
    const unitOrder = [
      SpeakSkill.vocabulary,
      SpeakSkill.speaking,
      SpeakSkill.reading,
      SpeakSkill.listening,
      SpeakSkill.writing,
    ];
    return unitOrder[position % unitOrder.length];
  }

  static SpeakSkill _courseSkillFor(SpeakSkill skill, int sequence) {
    // Course speaking is always the dedicated guided phrase flow. The
    // Practice app may offer Free Talk and Roleplay, but those are not
    // silently substituted into a Course lesson.
    if (skill == SpeakSkill.roleplay || skill == SpeakSkill.freeTalk) {
      return SpeakSkill.speaking;
    }
    return skill;
  }

  static List<_AdaptiveTemplate> _foundationTemplatesForLevel(String level) {
    if (level == 'A1') return _foundationTemplates;
    final descriptor = switch (level) {
      'A2' =>
        'Review the sound patterns that make everyday French easier to follow',
      'B1' => 'Refine sound patterns in connected French and natural speech',
      'B2' =>
        'Polish sound patterns, rhythm, and spelling clues in fluent speech',
      _ => 'Review the sound patterns that support the learner\'s level',
    };
    return [
      _t(
        'Review French sound patterns',
        '$descriptor, starting with the alphabet',
        SpeakSkill.alphabet,
        [SpeakSkill.listening, SpeakSkill.vocabulary],
        ['letter names', 'sound-spelling patterns'],
        ['Recognize the target sound patterns.', 'Explain one useful clue.'],
      ),
      _t(
        'Distinguish vowel contrasts',
        'hear and produce vowel contrasts in short, meaningful words',
        SpeakSkill.alphabet,
        [SpeakSkill.listening, SpeakSkill.speaking],
        ['French vowels', 'rhythm'],
        ['Distinguish the sounds.', 'Produce them in context.'],
      ),
      _t(
        'Use consonants in connected words',
        'recognize consonant changes and pronounce them in useful phrases',
        SpeakSkill.alphabet,
        [SpeakSkill.listening, SpeakSkill.vocabulary],
        ['French consonants', 'connected speech'],
        ['Notice the sound change.', 'Repeat the phrase clearly.'],
      ),
      _t(
        'Read accent clues in context',
        'use accent marks as clues while reading and listening',
        SpeakSkill.alphabet,
        [SpeakSkill.reading, SpeakSkill.listening],
        ['accent aigu', 'accent grave', 'accent circonflexe'],
        ['Identify the accent clue.', 'Read the word accurately.'],
      ),
      // Session 5 is the same authored self-introduction for every starting
      // level. It is a stable bridge from sound foundations into the first
      // personalized session, never another generated introduction.
      _foundationTemplates[4],
    ];
  }

  static int _minutes(String sessionLength, SpeakSkill skill) =>
      switch (sessionLength) {
        'quick' => 5,
        'deep' => skill == SpeakSkill.roleplay ? 20 : 18,
        _ => skill == SpeakSkill.roleplay ? 12 : 10,
      };

  static _AdaptiveTemplate _templateForFocus(
    List<_AdaptiveTemplate> templates,
    List<SpeakSkill> focusSkills, {
    required int sequence,
    required int cycle,
    Set<String> excludedTitles = const {},
  }) {
    final personalizedIndex = sequence - adaptiveCourseFoundationSize - 1;
    final target = focusSkills[personalizedIndex % focusSkills.length];
    final rotation = personalizedIndex ~/ focusSkills.length;
    final candidates = templates
        .where(
          (template) =>
              template.primary == target &&
              !_isIntroductionTemplate(template) &&
              !excludedTitles.contains(template.verb.toLowerCase()),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      final unused = templates
          .where(
            (template) =>
                !_isIntroductionTemplate(template) &&
                !excludedTitles.contains(template.verb.toLowerCase()),
          )
          .toList(growable: false);
      if (unused.isNotEmpty) {
        return unused[(rotation + cycle) % unused.length];
      }
      return _fallbackTemplateForSkill(target);
    }
    return candidates[(rotation + cycle) % candidates.length];
  }

  static bool _isIntroductionTemplate(_AdaptiveTemplate template) {
    final title = template.verb.toLowerCase();
    final competency = template.competency.toLowerCase();
    return title.contains('introduc') || competency.contains('introduc');
  }

  /// Goal-specific banks are intentionally small. This guarantees that every
  /// learner-facing focus can still own a lesson while the persisted context
  /// supplies the actual topic and goal adaptation.
  static _AdaptiveTemplate _fallbackTemplateForSkill(SpeakSkill skill) =>
      switch (skill) {
        SpeakSkill.speaking => _t(
          'Use French in context',
          'give a short, useful spoken response in the current situation',
          SpeakSkill.speaking,
          [SpeakSkill.listening, SpeakSkill.vocabulary],
          ['useful sentence patterns'],
          ['Respond clearly.', 'Add one relevant detail.'],
        ),
        SpeakSkill.listening => _t(
          'Listen for useful details',
          'understand the main idea and two details in the current situation',
          SpeakSkill.listening,
          [SpeakSkill.vocabulary, SpeakSkill.speaking],
          ['meaning from context'],
          ['Identify the main idea.', 'Confirm two details.'],
        ),
        SpeakSkill.reading => _t(
          'Read for meaning',
          'understand a short practical text in the current situation',
          SpeakSkill.reading,
          [SpeakSkill.vocabulary, SpeakSkill.grammar],
          ['sentence clues'],
          ['Find the main idea.', 'Explain one useful detail.'],
        ),
        SpeakSkill.writing => _t(
          'Write a useful message',
          'write a short message that achieves the current practical goal',
          SpeakSkill.writing,
          [SpeakSkill.vocabulary, SpeakSkill.grammar],
          ['clear sentence order', 'connectors'],
          ['State the purpose.', 'Add the needed detail.'],
        ),
        SpeakSkill.grammar => _t(
          'Build accurate sentences',
          'use one grammar pattern accurately in the current situation',
          SpeakSkill.grammar,
          [SpeakSkill.vocabulary, SpeakSkill.writing],
          ['one context-appropriate grammar pattern'],
          ['Recognize the pattern.', 'Use it in a new sentence.'],
        ),
        SpeakSkill.vocabulary => _t(
          'Learn five connected words',
          'understand and recall five useful words through one mini-story',
          SpeakSkill.vocabulary,
          [SpeakSkill.reading, SpeakSkill.speaking],
          ['word families and sentence context'],
          ['Recall all five words.', 'Understand each word in context.'],
        ),
        _ => _t(
          'Review useful French',
          'reuse recent French in the current situation',
          SpeakSkill.speaking,
          [SpeakSkill.vocabulary],
          ['recent language'],
          ['Recall the language.', 'Use it in context.'],
        ),
      };

  /// Course grows forever, but every goal's theme list is a fixed five
  /// entries, so a naive `themes[(unit - 1) % themes.length]` produces an
  /// exact, word-for-word repeat of an earlier unit's title once the
  /// learner passes unit 5 -- unit 6 showing "Alphabet & sound foundations"
  /// again, verbatim, despite being nowhere near the alphabet anymore, is
  /// confusing/looks like a bug even though the underlying lesson content
  /// is not actually duplicated. Repeating the same five themes forever is
  /// fine (the learner explicitly wants recurring practice); repeating the
  /// exact same TEXT is not. Mark every cycle past the first with a plain
  /// ordinal suffix so no two units ever show identical text.
  static String _unitThemeFor(List<String> themes, int unit) {
    final base = themes[(unit - 1) % themes.length];
    final cycle = (unit - 1) ~/ themes.length;
    if (cycle == 0) return base;
    const ordinals = ['II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
    final suffix = cycle - 1 < ordinals.length
        ? ordinals[cycle - 1]
        : '${cycle + 1}';
    return '$base $suffix';
  }

  static List<String> _unitThemesFor(String goal) => switch (goal) {
    'tef_canada' => const [
      'Exam and everyday foundations',
      'Instructions and key details',
      'Reasons and opinions',
      'Practical conversations',
      'Integrated exam practice',
    ],
    'work' => const [
      'Professional introductions',
      'Meetings and teamwork',
      'Messages and scheduling',
      'Interviews and goals',
      'Solving workplace problems',
    ],
    'relocation' => const [
      'Home and essential services',
      'Healthcare and appointments',
      'Forms and administration',
      'Family and community',
      'Daily independence',
    ],
    'travel' => const [
      'Arriving and getting around',
      'Food and shopping',
      'Plans and preferences',
      'Solving travel problems',
      'Meeting people',
    ],
    'culture' => const [
      'Personal stories',
      'Films and music',
      'Food and traditions',
      'Social conversations',
      'Opinions and reactions',
    ],
    _ => const [
      'Alphabet & sound foundations',
      'First words & introductions',
      'Everyday needs',
      'Integrated beginner conversations',
      'Beyond the basics',
    ],
  };

  static List<_AdaptiveTemplate> _templatesFor(
    String goal, {
    String level = 'A1',
  }) {
    final templates = switch (goal) {
      'tef_canada' => [
        _t(
          'Understand the main idea',
          'identify the main idea in an exam-style audio',
          SpeakSkill.listening,
          [SpeakSkill.vocabulary],
          ['question words'],
          ['Identify the main idea.', 'Find two key details.'],
        ),
        _t(
          'Ask for information',
          'obtain information in a structured interaction',
          SpeakSkill.speaking,
          [SpeakSkill.roleplay],
          ['question formation'],
          ['Ask three relevant questions.', 'React to the answer.'],
        ),
        _t(
          'Describe an experience',
          'describe a personal or practical experience',
          SpeakSkill.writing,
          [SpeakSkill.grammar],
          ['past narration'],
          ['Organize the event.', 'Use time markers.'],
        ),
        _t(
          'Compare two viewpoints',
          'compare two viewpoints and state a position',
          SpeakSkill.reading,
          [SpeakSkill.writing],
          ['comparisons', 'connectors'],
          ['Identify both viewpoints.', 'Give a supported opinion.'],
        ),
        _t(
          'Repair a misunderstanding',
          'ask for clarification and reformulate',
          SpeakSkill.speaking,
          [SpeakSkill.listening],
          ['clarification phrases'],
          ['Notice the misunderstanding.', 'Repair it politely.'],
        ),
        _t(
          'Follow a detailed instruction',
          'follow a sequence of instructions under time pressure',
          SpeakSkill.listening,
          [SpeakSkill.vocabulary],
          ['imperatives', 'sequence markers'],
          ['Order the steps.', 'Complete the task.'],
        ),
        _t(
          'Write a clear message',
          'write a concise message for a defined recipient',
          SpeakSkill.writing,
          [SpeakSkill.vocabulary],
          ['register', 'pronouns'],
          ['Address the recipient.', 'Include all required details.'],
        ),
        _t(
          'Express a reason',
          'give reasons and explain consequences',
          SpeakSkill.grammar,
          [SpeakSkill.speaking],
          ['parce que', 'donc', 'puisque'],
          ['Give two reasons.', 'Link cause and result.'],
        ),
        _t(
          'Infer meaning from context',
          'infer the meaning of an unfamiliar expression',
          SpeakSkill.reading,
          [SpeakSkill.vocabulary],
          ['context clues'],
          ['Use surrounding clues.', 'Choose the best interpretation.'],
        ),
        _t(
          'Speak with a time limit',
          'complete a focused oral response within a time limit',
          SpeakSkill.speaking,
          [SpeakSkill.review],
          ['discourse markers'],
          ['Answer directly.', 'End with a clear conclusion.'],
        ),
        _t(
          'Use high-value connectors',
          'connect ideas in a coherent response',
          SpeakSkill.connectors,
          [SpeakSkill.writing],
          ['connectors'],
          ['Join three ideas.', 'Avoid repetitive linking.'],
        ),
        _t(
          'Understand a public message',
          'understand an announcement and its practical consequence',
          SpeakSkill.listening,
          [SpeakSkill.vocabulary],
          ['negation', 'numbers'],
          ['Extract the action required.', 'Identify the time or place.'],
        ),
        _t(
          'Defend a preference',
          'defend a preference with examples',
          SpeakSkill.speaking,
          [SpeakSkill.vocabulary],
          ['opinion phrases'],
          ['State a preference.', 'Support it with an example.'],
        ),
        _t(
          'Read for specific details',
          'scan a practical document for exact information',
          SpeakSkill.reading,
          [SpeakSkill.vocabulary],
          ['dates', 'quantities'],
          ['Locate four details.', 'Ignore irrelevant information.'],
        ),
        _t(
          'Write a short argument',
          'write a short argument with a clear position',
          SpeakSkill.writing,
          [SpeakSkill.connectors],
          ['opinion structure'],
          ['State a position.', 'Support it with two points.'],
        ),
        _t(
          'Describe a change',
          'describe a change over time',
          SpeakSkill.grammar,
          [SpeakSkill.speaking],
          ['present and past contrast'],
          ['Describe before and after.', 'Use a time reference.'],
        ),
        _t(
          'Respond to a problem',
          'propose a practical solution to a problem',
          SpeakSkill.roleplay,
          [SpeakSkill.speaking],
          ['conditional politeness'],
          ['Explain the problem.', 'Propose a solution.'],
        ),
        _t(
          'Summarize information',
          'summarize the essential information from a source',
          SpeakSkill.reading,
          [SpeakSkill.writing],
          ['reported information'],
          ['Keep the key facts.', 'Avoid copying every detail.'],
        ),
        _t(
          'Use appropriate register',
          'choose a formal or informal register for the audience',
          SpeakSkill.writing,
          [SpeakSkill.grammar],
          ['formal requests'],
          ['Identify the audience.', 'Adjust the wording.'],
        ),
        _t(
          'Complete an integrated task',
          'combine comprehension and production in one exam-style task',
          SpeakSkill.review,
          [SpeakSkill.listening, SpeakSkill.writing],
          ['review of prior targets'],
          ['Complete the task independently.', 'Explain one improvement.'],
        ),
      ],
      'work' => _workTemplates,
      'relocation' => _relocationTemplates,
      'travel' => _travelTemplates,
      'culture' => _cultureTemplates,
      _ => _everydayTemplates,
    };
    return templates;
  }

  static _AdaptiveTemplate _templateForPhase(
    _AdaptiveTemplate fallback, {
    required String level,
    required SpeakSkill primarySkill,
    required int sequence,
  }) {
    if (sequence <= adaptiveCourseSimplePhaseEnd &&
        sequence > adaptiveCourseFoundationSize) {
      return _earlyTemplateForLevel(level, primarySkill, sequence);
    }
    return _calibrateTemplateForLevel(fallback, level);
  }

  /// The first fifteen personalised lessons deliberately borrow the small
  /// building blocks already used by Practice. This is a course-wide rule:
  /// the topic can come from onboarding/recent evidence, but the activity
  /// shape stays controlled until the learner has a little momentum.
  static _AdaptiveTemplate _earlyTemplateForLevel(
    String level,
    SpeakSkill skill,
    int sequence,
  ) {
    final band = level.trim().toUpperCase();
    final variant = (sequence - adaptiveCourseFoundationSize - 1) % 3;
    final a1 = band == 'A1';
    final a2 = band == 'A2';
    final b1 = band == 'B1';
    final title = switch (skill) {
      SpeakSkill.speaking => _pick(
        a1
            ? const [
                'Ask a simple question',
                'Say what you need',
                'Say what you like',
              ]
            : a2
            ? const [
                'Talk about your day',
                'Ask for information',
                'Make a simple plan',
              ]
            : b1
            ? const [
                'Share a short experience',
                'Give a short reason',
                'Make a short plan',
              ]
            : const [
                'Share a clear experience',
                'Explain a simple reason',
                'Make a clear plan',
              ],
        variant,
      ),
      SpeakSkill.listening => _pick(
        a1
            ? const ['Hear a name', 'Hear a number', 'Hear a place']
            : a2
            ? const [
                'Catch the main point',
                'Follow simple instructions',
                'Find key details',
              ]
            : b1
            ? const [
                'Follow a short conversation',
                'Catch important details',
                'Understand the main point',
              ]
            : const [
                'Follow a connected conversation',
                'Catch the key details',
                'Understand the speaker',
              ],
        variant,
      ),
      SpeakSkill.reading => _pick(
        a1
            ? const [
                'Read a short message',
                'Read a simple sign',
                'Find a name',
              ]
            : a2
            ? const [
                'Read a short message',
                'Read a practical note',
                'Find key information',
              ]
            : b1
            ? const [
                'Read a practical text',
                'Find the main idea',
                'Connect key details',
              ]
            : const [
                'Read a useful text',
                'Find the central idea',
                'Connect the details',
              ],
        variant,
      ),
      SpeakSkill.writing => _pick(
        a1
            ? const [
                'Build a short sentence',
                'Write a simple note',
                'Write a short reply',
              ]
            : a2
            ? const [
                'Write a short message',
                'Describe a routine',
                'Make a simple request',
              ]
            : b1
            ? const [
                'Write a clear message',
                'Describe an experience',
                'State an opinion',
              ]
            : const [
                'Write a clear message',
                'Describe an experience',
                'State a position',
              ],
        variant,
      ),
      SpeakSkill.grammar => _pick(
        a1
            ? const ['Use être', 'Use avoir', 'Ask a question']
            : a2
            ? const ['Use the past', 'Use the near future', 'Join two ideas']
            : b1
            ? const ['Use past time', 'Explain a reason', 'Link two ideas']
            : const [
                'Control past time',
                'Explain a reason',
                'Link ideas clearly',
              ],
        variant,
      ),
      SpeakSkill.vocabulary => _pick(
        a1
            ? const [
                'Learn common words',
                'Learn people words',
                'Learn food words',
              ]
            : a2
            ? const [
                'Build everyday phrases',
                'Talk about places',
                'Talk about plans',
              ]
            : b1
            ? const [
                'Use useful phrases',
                'Talk about work',
                'Describe an experience',
              ]
            : const [
                'Use precise phrases',
                'Talk about work',
                'Describe an experience',
              ],
        variant,
      ),
      _ => 'Review useful French',
    };

    final competency = switch (skill) {
      SpeakSkill.speaking => _pick(
        a1
            ? const [
                'ask one short everyday question',
                'say one simple need',
                'say one simple preference',
              ]
            : a2
            ? const [
                'say three short things about your day',
                'ask one clear everyday question',
                'say one plan and when it happens',
              ]
            : b1
            ? const [
                'tell a short experience in order',
                'give one reason for a choice',
                'describe one future plan',
              ]
            : const [
                'tell a clear short experience',
                'support a choice with a reason',
                'describe a plan with one detail',
              ],
        variant,
      ),
      SpeakSkill.listening => _pick(
        a1
            ? const [
                'understand a name in a short line',
                'understand one number',
                'understand one place word',
              ]
            : a2
            ? const [
                'understand the main idea',
                'follow two simple steps',
                'find two useful details',
              ]
            : b1
            ? const [
                'understand a short exchange',
                'find the important details',
                'identify the speaker’s point',
              ]
            : const [
                'follow a connected exchange',
                'select the relevant details',
                'summarize the speaker’s point',
              ],
        variant,
      ),
      SpeakSkill.reading => _pick(
        a1
            ? const [
                'read one short practical line',
                'understand a common sign',
                'find a person’s name',
              ]
            : a2
            ? const [
                'understand a short message',
                'understand a practical note',
                'find key information',
              ]
            : b1
            ? const [
                'understand a practical text',
                'identify the main idea',
                'connect details in a text',
              ]
            : const [
                'understand a useful text',
                'identify the central idea',
                'connect supporting details',
              ],
        variant,
      ),
      SpeakSkill.writing => _pick(
        a1
            ? const [
                'put a few words in order',
                'write one simple note',
                'write one short reply',
              ]
            : a2
            ? const [
                'write a short message',
                'describe a simple routine',
                'make a clear request',
              ]
            : b1
            ? const [
                'write a clear practical message',
                'describe a recent experience',
                'state and support an opinion',
              ]
            : const [
                'write a clear practical message',
                'describe an experience clearly',
                'state and support a position',
              ],
        variant,
      ),
      SpeakSkill.grammar => _pick(
        a1
            ? const [
                'use être in one sentence',
                'use avoir in one sentence',
                'ask one simple question',
              ]
            : a2
            ? const [
                'use one past pattern',
                'use futur proche',
                'join two short ideas',
              ]
            : b1
            ? const [
                'use past time accurately',
                'link a reason and result',
                'join ideas clearly',
              ]
            : const [
                'control past time accurately',
                'link a reason and result',
                'join ideas with nuance',
              ],
        variant,
      ),
      SpeakSkill.vocabulary => _pick(
        a1
            ? const [
                'recognize five common words',
                'recognize words for people',
                'recognize five food words',
              ]
            : a2
            ? const [
                'use five everyday phrases',
                'use words for places',
                'use words for plans',
              ]
            : b1
            ? const [
                'reuse five useful phrases',
                'use workplace words',
                'describe an experience with useful words',
              ]
            : const [
                'reuse precise useful phrases',
                'use workplace vocabulary',
                'describe an experience accurately',
              ],
        variant,
      ),
      _ => 'reuse recent French in a short situation',
    };

    final grammar = switch (skill) {
      SpeakSkill.speaking =>
        a1
            ? const ['ça va ?', 'je voudrais', 'j’aime']
            : a2
            ? const ['présent', 'questions', 'aller + infinitive']
            : b1
            ? const ['time markers', 'parce que', 'future']
            : const ['time markers', 'parce que', 'future contrast'],
      SpeakSkill.listening =>
        a1
            ? const ['names', 'numbers', 'places']
            : a2
            ? const ['question words', 'sequence words', 'time words']
            : const ['question words', 'sequence markers', 'time markers'],
      SpeakSkill.reading =>
        a1
            ? const ['articles', 'common signs', 'names']
            : a2
            ? const ['message words', 'dates', 'places']
            : const ['text clues', 'dates', 'connectors'],
      SpeakSkill.writing =>
        a1
            ? const ['word order', 'je suis', 'merci']
            : a2
            ? const ['word order', 'present tense', 'polite requests']
            : const ['clear order', 'time markers', 'connectors'],
      SpeakSkill.grammar =>
        a1
            ? const ['être', 'avoir', 'question words']
            : a2
            ? const ['passé composé', 'futur proche', 'et/mais']
            : const ['past time', 'cause and result', 'connectors'],
      SpeakSkill.vocabulary =>
        a1
            ? const ['common words', 'people', 'food']
            : a2
            ? const ['everyday phrases', 'places', 'plans']
            : const ['useful phrases', 'work', 'experiences'],
      _ => const ['recent targets'],
    };

    final success = a1
        ? const [
            'Complete the small guided check.',
            'Use one target in a new short example.',
          ]
        : a2
        ? const [
            'Complete the controlled check.',
            'Use the target in one clear example.',
          ]
        : const [
            'Complete the focused practice.',
            'Transfer the target to one new example.',
          ];
    return _t(
      title,
      competency,
      skill,
      _supportingFor(skill),
      grammar,
      success,
    );
  }

  static List<SpeakSkill> _supportingFor(SpeakSkill skill) => switch (skill) {
    SpeakSkill.speaking => const [SpeakSkill.vocabulary, SpeakSkill.listening],
    SpeakSkill.listening => const [SpeakSkill.vocabulary, SpeakSkill.speaking],
    SpeakSkill.reading => const [SpeakSkill.vocabulary, SpeakSkill.grammar],
    SpeakSkill.writing => const [SpeakSkill.vocabulary, SpeakSkill.grammar],
    SpeakSkill.grammar => const [SpeakSkill.vocabulary, SpeakSkill.writing],
    SpeakSkill.vocabulary => const [SpeakSkill.reading, SpeakSkill.speaking],
    _ => const [SpeakSkill.vocabulary],
  };

  static String _pick(List<String> values, int index) =>
      values[index % values.length];

  static List<String> _safeTargetPhrases(
    String level,
    List<String> targets, {
    required List<String> fallback,
  }) {
    final normalized = level.trim().toUpperCase();
    final maxWords = normalized == 'A1'
        ? 6
        : normalized == 'A2'
        ? 9
        : 14;
    final blocked = RegExp(
      r'\b(conditionnel|subjonctif|à condition que|bien que|cependant|pourtant)\b',
      caseSensitive: false,
    );
    final safe = targets
        .map((value) => value.trim())
        .where(
          (value) =>
              value.isNotEmpty &&
              value.split(RegExp(r'\s+')).length <= maxWords &&
              !blocked.hasMatch(value),
        )
        .take(6)
        .toList(growable: false);
    return safe.isEmpty ? fallback.take(6).toList(growable: false) : safe;
  }

  /// The competency bank is shared across levels, but its language target is
  /// not. Keep the same skill rotation while replacing advanced A1/A2
  /// requirements (conditions, arguments, and past narration) with a small
  /// beginner-sized task before it is persisted into the learner's plan.
  static _AdaptiveTemplate _calibrateTemplateForLevel(
    _AdaptiveTemplate template,
    String level,
  ) {
    final normalized = level.trim().toUpperCase();
    if (normalized != 'A1' && normalized != 'A2') return template;

    final title = template.verb.toLowerCase();
    if (title == 'speak about a plan') {
      return _t(
        normalized == 'A1' ? 'Talk about tomorrow' : 'Talk about a plan',
        normalized == 'A1'
            ? 'say one simple plan for tomorrow'
            : 'say a simple near-future plan and ask one follow-up',
        template.primary,
        template.supporting,
        normalized == 'A1'
            ? ['present tense', 'time words']
            : ['aller', 'demain'],
        normalized == 'A1'
            ? ['Say one simple plan.', 'Add when.']
            : ['State the plan.', 'Ask one follow-up.'],
      );
    }
    if (title == 'describe a past event') {
      return _t(
        normalized == 'A1' ? 'Talk about your day' : 'Describe a recent event',
        normalized == 'A1'
            ? 'say three simple things about your daily routine'
            : 'tell a short recent event with simple time markers',
        template.primary,
        template.supporting,
        normalized == 'A1'
            ? ['present tense', 'time words']
            : ['passé composé'],
        normalized == 'A1'
            ? ['Say three short sentences.', 'Use a time word.']
            : ['Put the event in order.', 'Use two time markers.'],
      );
    }
    if (title == 'express a reason' || title == 'defend a preference') {
      return _t(
        normalized == 'A1' ? 'Say what you like' : 'Explain a preference',
        normalized == 'A1'
            ? 'say what you like and ask one simple question'
            : 'state a preference and give one simple reason',
        template.primary,
        template.supporting,
        normalized == 'A1' ? ['aimer', 'et'] : ['parce que', 'mais'],
        normalized == 'A1'
            ? ['Say one preference.', 'Ask one question.']
            : ['State the preference.', 'Give one reason.'],
      );
    }
    if (title == 'make a polite request' || title == 'respond to a problem') {
      return _t(
        normalized == 'A1' ? 'Ask for help' : 'Make a polite request',
        normalized == 'A1'
            ? 'ask for one everyday thing with a polite phrase'
            : 'make a clear polite request in an everyday situation',
        template.primary,
        template.supporting,
        normalized == 'A1'
            ? ['je voudrais', 's’il vous plaît']
            : ['polite requests'],
        normalized == 'A1'
            ? ['Say the request.', 'Use please.']
            : ['Make the request.', 'Respond to the answer.'],
      );
    }
    if (title == 'connect two ideas' || title == 'use high-value connectors') {
      return _t(
        normalized == 'A1' ? 'Join two ideas' : 'Connect two ideas',
        normalized == 'A1'
            ? 'join two short sentences with et or mais'
            : 'join two everyday ideas in one clear response',
        template.primary,
        template.supporting,
        normalized == 'A1' ? ['et', 'mais'] : ['parce que', 'mais', 'donc'],
        normalized == 'A1'
            ? ['Join two short ideas.', 'Keep the sentence clear.']
            : ['Connect the ideas.', 'Keep the response coherent.'],
      );
    }
    if (title == 'write a short argument' ||
        title == 'compare two viewpoints') {
      return _t(
        normalized == 'A1' ? 'Write a simple opinion' : 'Compare two choices',
        normalized == 'A1'
            ? 'write two short sentences about a simple choice'
            : 'compare two everyday choices and state a preference',
        template.primary,
        template.supporting,
        normalized == 'A1' ? ['aimer', 'mais'] : ['comparisons', 'connectors'],
        normalized == 'A1'
            ? ['State your choice.', 'Add one detail.']
            : ['Compare the choices.', 'State a preference.'],
      );
    }
    return template;
  }

  static _AdaptiveTemplate _t(
    String verb,
    String competency,
    SpeakSkill primary,
    List<SpeakSkill> supporting,
    List<String> grammar,
    List<String> success,
  ) => _AdaptiveTemplate(
    verb: verb,
    competency: competency,
    primary: primary,
    supporting: supporting,
    grammar: grammar,
    success: success,
  );

  static final _everydayTemplates = [
    _t(
      'Introduce yourself naturally',
      'introduce yourself and ask a follow-up question',
      SpeakSkill.speaking,
      [SpeakSkill.vocabulary],
      ['être', 'avoir'],
      ['Give personal information.', 'Ask one follow-up question.'],
    ),
    _t(
      'Handle an appointment',
      'make, change, or confirm an appointment',
      SpeakSkill.roleplay,
      [SpeakSkill.listening],
      ['questions', 'dates'],
      ['State the purpose.', 'Confirm the time.'],
    ),
    _t(
      'Ask for clarification',
      'ask someone to repeat or explain',
      SpeakSkill.listening,
      [SpeakSkill.speaking],
      ['question words'],
      ['Use two repair phrases.', 'Confirm your understanding.'],
    ),
    _t(
      'Talk about your routine',
      'describe a routine and one change',
      SpeakSkill.grammar,
      [SpeakSkill.speaking],
      ['present tense', 'frequency'],
      ['Describe a routine.', 'Mention a change.'],
    ),
    _t(
      'Make a useful choice',
      'compare options and make a choice',
      SpeakSkill.vocabulary,
      [SpeakSkill.speaking],
      ['comparisons'],
      ['Compare two options.', 'Give a reason.'],
    ),
    _t(
      'Write a short message',
      'write a practical message to another person',
      SpeakSkill.writing,
      [SpeakSkill.vocabulary],
      ['register'],
      ['Include the purpose.', 'Close the message naturally.'],
    ),
    _t(
      'Understand a short story',
      'follow a short story and identify the change',
      SpeakSkill.reading,
      [SpeakSkill.vocabulary],
      ['past and present'],
      ['Identify the setting.', 'Explain what changed.'],
    ),
    _t(
      'Speak about a plan',
      'talk about a future plan and a condition',
      SpeakSkill.speaking,
      [SpeakSkill.grammar],
      ['future', 'si'],
      ['State the plan.', 'Explain one condition.'],
    ),
    _t(
      'Connect two ideas',
      'join ideas into a clear response',
      SpeakSkill.connectors,
      [SpeakSkill.writing],
      ['parce que', 'mais', 'donc'],
      ['Connect three ideas.', 'Keep the response coherent.'],
    ),
    _t(
      'Solve a small problem',
      'explain a problem and request help',
      SpeakSkill.roleplay,
      [SpeakSkill.speaking],
      ['polite requests'],
      ['Explain the problem.', 'Request a specific action.'],
    ),
    _t(
      'Listen for key details',
      'identify names, dates, places, and actions',
      SpeakSkill.listening,
      [SpeakSkill.vocabulary],
      ['numbers', 'dates'],
      ['Capture four details.', 'Explain the next action.'],
    ),
    _t(
      'Describe a past event',
      'tell a short past event in order',
      SpeakSkill.writing,
      [SpeakSkill.grammar],
      ['passé composé'],
      ['Use a beginning and ending.', 'Use two time markers.'],
    ),
    _t(
      'Give an opinion',
      'state an opinion and support it',
      SpeakSkill.speaking,
      [SpeakSkill.vocabulary],
      ['opinion phrases'],
      ['State an opinion.', 'Give one example.'],
    ),
    _t(
      'Read practical information',
      'find exact information in a practical document',
      SpeakSkill.reading,
      [SpeakSkill.vocabulary],
      ['imperatives'],
      ['Find the required details.', 'Explain what to do.'],
    ),
    _t(
      'Sound more natural',
      'use pronunciation and liaison in connected speech',
      SpeakSkill.liaison,
      [SpeakSkill.speaking],
      ['liaison'],
      ['Produce the target phrases.', 'Keep a natural rhythm.'],
    ),
    _t(
      'Describe a preference',
      'describe preferences and ask about another person',
      SpeakSkill.vocabulary,
      [SpeakSkill.speaking],
      ['aimer', 'préférer'],
      ['Explain a preference.', 'Ask the other person.'],
    ),
    _t(
      'Give directions clearly',
      'give and follow simple directions',
      SpeakSkill.listening,
      [SpeakSkill.speaking],
      ['imperatives', 'locations'],
      ['Give three steps.', 'Check understanding.'],
    ),
    _t(
      'Make a polite request',
      'make a request with the right level of politeness',
      SpeakSkill.grammar,
      [SpeakSkill.roleplay],
      ['conditionnel de politesse'],
      ['Make the request.', 'Respond to a refusal.'],
    ),
    _t(
      'Review and transfer',
      'reuse recent language in a new situation',
      SpeakSkill.review,
      [SpeakSkill.speaking, SpeakSkill.writing],
      ['recent targets'],
      ['Use three recent targets.', 'Adapt them to a new context.'],
    ),
    _t(
      'Complete a real-life conversation',
      'combine the route skills in a realistic conversation',
      SpeakSkill.roleplay,
      [SpeakSkill.listening, SpeakSkill.speaking],
      ['route review'],
      ['Reach the conversation goal.', 'Reflect on one next step.'],
    ),
  ];

  static final _foundationTemplates = [
    _t(
      'Recognize French sounds',
      'recognize the French alphabet and core sound patterns',
      SpeakSkill.alphabet,
      [SpeakSkill.listening, SpeakSkill.vocabulary],
      ['letter names', 'vowels'],
      ['Recognize the target sounds.', 'Repeat them accurately.'],
    ),
    _t(
      'Build vowel confidence',
      'distinguish and pronounce the core French vowel sounds',
      SpeakSkill.alphabet,
      [SpeakSkill.listening, SpeakSkill.speaking],
      ['French vowels'],
      ['Distinguish the sounds.', 'Produce the target words.'],
    ),
    _t(
      'Notice French consonants',
      'recognize the consonant names and the few sounds beginners often confuse',
      SpeakSkill.alphabet,
      [SpeakSkill.listening, SpeakSkill.vocabulary],
      ['French consonants'],
      ['Recognize the target consonants.', 'Repeat the names clearly.'],
    ),
    _t(
      'Recognize core accent marks',
      'tell accent aigu, accent grave, and accent circonflexe apart',
      SpeakSkill.alphabet,
      [SpeakSkill.listening, SpeakSkill.vocabulary],
      ['accent aigu', 'accent grave', 'accent circonflexe'],
      ['Name each mark.', 'Explain its beginner-friendly sound clue.'],
    ),
    _t(
      'Introduce yourself',
      'say your name, where you are from, and one simple personal detail',
      SpeakSkill.speaking,
      [SpeakSkill.vocabulary, SpeakSkill.listening],
      ['être', 's’appeler', 'venir de'],
      ['Say your name and origin.', 'Add one simple personal detail.'],
    ),
  ];

  // The learner's goal changes the situation/context and unit theme. It does
  // not need to be repeated in every lesson heading.
  static final _workTemplates = _everydayTemplates;
  static final _relocationTemplates = _everydayTemplates;
  static final _travelTemplates = _everydayTemplates;
  static final _cultureTemplates = _everydayTemplates;
}

class _AdaptiveTemplate {
  const _AdaptiveTemplate({
    required this.verb,
    required this.competency,
    required this.primary,
    required this.supporting,
    required this.grammar,
    required this.success,
  });

  final String verb;
  final String competency;
  final SpeakSkill primary;
  final List<SpeakSkill> supporting;
  final List<String> grammar;
  final List<String> success;
}
