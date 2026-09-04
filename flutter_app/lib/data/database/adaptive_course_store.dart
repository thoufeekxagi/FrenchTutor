import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../services/adaptive_curriculum_service.dart';
import '../../services/universal_learning_data_service.dart';
import 'app_migrations.dart';

const _adaptiveUuid = Uuid();

/// The unit of course progression shared by onboarding, Home, Course, and
/// the speaking pathway. A block is generated lazily as specifications; the
/// rich lesson is still created only when the learner opens a session.
const adaptiveCourseBlockSize = 20;

/// One planned session in the learner's current adaptive route.
///
/// This is intentionally a specification, not the final story/quiz payload.
/// It gives the Home/Course screens something immediate to render while the
/// existing practice engines generate the rich lesson when the learner opens
/// it. The specification is stable once the session is completed.
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
  final String profileFingerprint;
  final String status; // planned | active | completed | replaced
  final DateTime createdAt;
  final DateTime? completedAt;

  /// Zero-based block number. Session 1–20 are block 0, 21–40 are block 1,
  /// and so on. Keeping this derived from the stable sequence means no schema
  /// migration is needed and synced rows remain backwards compatible.
  int get blockIndex => (sequence - 1) ~/ adaptiveCourseBlockSize;

  /// One-based position within the current twenty-session block.
  int get blockPosition => ((sequence - 1) % adaptiveCourseBlockSize) + 1;

  String get targetPhrasePrompt => targetPhrases.isEmpty
      ? 'Choose from the competency.'
      : targetPhrases.join('; ');

  String get learningMix =>
      'Reuse recent learner language for about 60% of the session and add about 40% new language.';

  /// The learner-facing phase of the shared course route. Keeping this on the
  /// stable session specification lets Course, Home, Practice, and Speaking
  /// describe the same progression without each screen inventing its own
  /// lesson order.
  String get learningPhase => switch (sequence) {
    1 => 'Sound foundation: recognize the French alphabet.',
    2 => 'Sound foundation: hear and produce French vowels.',
    3 => 'Sound foundation: hear and produce French consonants.',
    4 => 'Sound foundation: notice accents and spelling clues.',
    5 => 'Sound foundation: connect sound, spelling, and meaning.',
    6 || 11 || 16 => 'Discover the key words for this unit.',
    7 || 12 || 17 => 'Use the words in a controlled sentence.',
    8 || 13 || 18 => 'Read the language in a short, useful context.',
    9 || 14 || 19 => 'Listen for the same meaning in connected speech.',
    10 || 15 || 20 => 'Speak and reuse the unit language in a short exchange.',
    _ => 'Transfer and repair recent language in a new situation.',
  };

  String get contextPrompt =>
      '''PERSONALIZED COURSE SESSION
Goal: ${subtitle.split(' · ').first}
CEFR level: $level
Competency: $competency
Situation: $context
Primary skill: ${primarySkill.label}
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
/// The store creates twenty lightweight lesson specifications immediately.
/// The first lesson can open without waiting for the rest, while the remaining
/// specifications are already available to Home/Course. After the learner
/// completes the twentieth session in the current block, the next twenty are
/// appended in the same local transaction on the next plan refresh. A profile
/// change replaces only unfinished future sessions and copies completed
/// sessions into the new plan version.
class AdaptiveCourseStore {
  AdaptiveCourseStore(this._db, {this._onPlanChanged, this._onSessionChanged}) {
    runAppMigrations(_db);
    _ensureLearningEvidenceColumns();
  }

  final CommonDatabase _db;
  final Future<void> Function(AdaptiveCoursePlanSnapshot plan)? _onPlanChanged;
  final Future<void> Function(AdaptiveCourseSessionSpec session)?
  _onSessionChanged;

  static const initialBatchSize = adaptiveCourseBlockSize;
  // Add the next block before the learner reaches the last few sessions. The
  // adaptive rows are lightweight specifications, so this does not make the
  // learner wait for rich lesson generation when they finish a block.
  static const replanThreshold = 5;

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
      if (reconciled.sessions
              .where((session) => session.status != 'completed')
              .length <=
          replanThreshold) {
        _appendBatch(
          planId: reconciled.id,
          profile: profile,
          profileFingerprint: fingerprint,
          startSequence: _nextSequence(reconciled.sessions),
          batchSize: initialBatchSize,
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
    _db.execute(
      "UPDATE adaptive_course_sessions SET status = 'active', updated_at = ? "
      "WHERE plan_id = ? AND content_key = ? AND status = 'planned' AND deleted_at IS NULL",
      [_now(), plan['id'], contentKey],
    );
    final session = _sessionByContentKey(plan['id'] as String, contentKey);
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
    return snapshot == null
        ? profileFingerprint
        : profileFingerprint + '|learning:' + snapshot.fingerprint;
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
  /// completion state. The initial route is always contiguous from sequence 1
  /// through 20; later gaps are repaired up to the highest known sequence.
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
      // the staged Unit 1–4 curriculum without losing its stable id, status,
      // or progress key. Completed rows remain historical records.
      if (session.sequence <= initialBatchSize &&
          current.status != 'completed' &&
          current.status != 'replaced' &&
          _needsCurriculumUpgrade(current, session, profileFingerprint)) {
        _updatePlannedSessionSpec(
          current,
          session,
          profileFingerprint: profileFingerprint,
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
    return current.level != replacement.level ||
        current.unit != replacement.unit ||
        current.unitTitle != replacement.unitTitle ||
        current.title != replacement.title ||
        current.subtitle != replacement.subtitle ||
        current.competency != replacement.competency ||
        current.context != replacement.context ||
        current.primarySkill != replacement.primarySkill ||
        current.supportingSkills.map((skill) => skill.wireName).join('|') !=
            replacement.supportingSkills
                .map((skill) => skill.wireName)
                .join('|') ||
        current.grammarFocus.join('|') != replacement.grammarFocus.join('|') ||
        current.successCriteria.join('|') !=
            replacement.successCriteria.join('|') ||
        current.estimatedMinutes != replacement.estimatedMinutes ||
        current.targetPhrases.join('|') !=
            replacement.targetPhrases.join('|') ||
        current.sourceSessionIds.join('|') !=
            replacement.sourceSessionIds.join('|') ||
        current.profileFingerprint != profileFingerprint;
  }

  void _updatePlannedSessionSpec(
    AdaptiveCourseSessionSpec current,
    AdaptiveCourseSessionSpec replacement, {
    required String profileFingerprint,
  }) {
    _db.execute(
      '''UPDATE adaptive_course_sessions
         SET level = ?, unit = ?, unit_title = ?, title = ?, subtitle = ?,
             competency = ?, context = ?, primary_skill = ?,
             supporting_skills_json = ?, grammar_focus_json = ?,
             success_criteria_json = ?, estimated_minutes = ?,
             target_phrases_json = ?, source_session_ids_json = ?,
             profile_fingerprint = ?, updated_at = ?
         WHERE id = ? AND status NOT IN ('completed', 'replaced')
           AND deleted_at IS NULL''',
      [
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
        _now(),
        current.id,
      ],
    );
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
         status, created_at, updated_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
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
          profile_fingerprint, status, created_at, updated_at, completed_at,
          deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
/// content is still generated by the existing lesson engines from each slot's
/// context prompt, so the first route appears immediately without waiting for
/// twenty network calls.
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
    final focusSkills = recentFocusSkills.isEmpty
        ? AdaptiveCurriculumService.focusSkills(profile)
        : recentFocusSkills;
    final templates = _templatesFor(profile.goal);
    final unitThemes = _unitThemesFor(profile.goal);
    final sessions = <AdaptiveCourseSessionSpec>[];
    for (var offset = 0; offset < count; offset++) {
      final sequence = startSequence + offset;
      final cycle = (sequence - 1) ~/ templates.length;
      final guidedPathTemplate = _guidedPathTemplate(level, sequence);
      final template =
          guidedPathTemplate ??
          _reservedSpeakingTemplate(templates, sequence) ??
          _templateForFocus(
            templates,
            focusSkills,
            sequence: sequence,
            cycle: cycle,
          );
      final baseContext =
          track.contexts[(sequence - 1) % track.contexts.length];
      final foundationBase =
          'French pronunciation foundations for $baseContext';
      final foundationContext = interest == null
          ? foundationBase
          : '$foundationBase with a light connection to $interest';
      final isFoundation = sequence <= 5;
      final context = isFoundation
          ? foundationContext
          : interest == null
          ? baseContext
          : '$baseContext with a light connection to $interest';
      final personalizedContext =
          learningSnapshot?.contextForLesson(
            sequence: sequence,
            baseContext: context,
          ) ??
          context;
      final targetPhrases =
          learningSnapshot?.targetsForLesson(
            sequence: sequence,
            fallback: template.grammar,
          ) ??
          template.grammar;
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
      final unitTheme = unitThemes[(unit - 1) % unitThemes.length];
      final title = template.verb;
      final subtitle = cycle == 0
          ? '${track.label} · ${template.competency}'
          : '${track.label} · Transfer practice · ${template.competency}';
      sessions.add(
        AdaptiveCourseSessionSpec(
          id: _adaptiveUuid.v4(),
          planId: planId,
          contentKey:
              'adaptive_${planId}_s${sequence.toString().padLeft(3, '0')}',
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
          primarySkill: template.primary,
          supportingSkills: supportingSkills,
          grammarFocus: template.grammar,
          successCriteria: template.success,
          estimatedMinutes: _minutes(profile.sessionLength, template.primary),
          targetPhrases: targetPhrases,
          sourceSessionIds:
              learningSnapshot?.sourceSessionIds
                  .take(12)
                  .toList(growable: false) ??
              const <String>[],
          profileFingerprint: profileFingerprint,
          status: 'planned',
          createdAt: DateTime.now(),
        ),
      );
    }
    return sessions;
  }

  /// The first twenty sessions are a deliberate beginner route rather than a
  /// rotation of unrelated focus skills. Every five-session unit follows the
  /// same teach-and-transfer rhythm:
  /// vocabulary → grammar → reading → listening → speaking/review.
  ///
  /// Later blocks remain adaptive and are generated from the learner profile,
  /// but they continue from this shared foundation instead of replacing it.
  static _AdaptiveTemplate? _guidedPathTemplate(String level, int sequence) {
    if (sequence <= 5) {
      return _foundationTemplatesForLevel(level)[sequence - 1];
    }
    if (sequence <= 20) {
      return _levelledTemplate(level, _integratedPathTemplates[sequence - 6]);
    }
    return null;
  }

  static _AdaptiveTemplate _levelledTemplate(
    String level,
    _AdaptiveTemplate base,
  ) {
    final levelGrammar = switch (level) {
      'A1' => 'fixed phrases and the present tense',
      'A2' => 'past and near-future forms with simple reasons',
      'B1' => 'connectors, time frames, and supported opinions',
      'B2' => 'nuance, reformulation, and formal or informal register',
      _ => 'the learner\'s current CEFR grammar',
    };
    final levelSuccess = switch (level) {
      'A1' => 'Keep the response to one or two clear sentences.',
      'A2' => 'Link several short ideas and add one reason.',
      'B1' => 'Organize the response with a clear beginning and follow-up.',
      'B2' =>
        'Choose precise wording and adjust the register to the situation.',
      _ => 'Use the target grammar accurately in context.',
    };
    return _AdaptiveTemplate(
      verb: base.verb,
      competency: '${base.competency} at $level level',
      primary: base.primary,
      supporting: base.supporting,
      grammar: [...base.grammar, levelGrammar],
      success: [...base.success, levelSuccess],
    );
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
      _t(
        'Connect sound to meaning',
        'reuse essential words with accurate spelling and pronunciation',
        SpeakSkill.vocabulary,
        [SpeakSkill.alphabet, SpeakSkill.speaking],
        ['spelling and pronunciation', 'word families'],
        ['Read the words.', 'Use them in a short response.'],
      ),
    ];
  }

  static final _integratedPathTemplates = <_AdaptiveTemplate>[
    _t(
      'Learn first-meeting words',
      'recognize greetings, names, countries, and personal information',
      SpeakSkill.vocabulary,
      [SpeakSkill.alphabet, SpeakSkill.grammar],
      ['greetings', 'names', 'countries', 'être'],
      ['Recognize the key words.', 'Use three words in a short phrase.'],
    ),
    _t(
      'Build a first introduction',
      'make a clear first sentence about yourself',
      SpeakSkill.grammar,
      [SpeakSkill.vocabulary, SpeakSkill.speaking],
      ['subject pronouns', 'être', 'avoir'],
      ['Choose the correct subject and verb.', 'Build one accurate sentence.'],
    ),
    _t(
      'Read a short introduction',
      'understand a short introduction and find personal details',
      SpeakSkill.reading,
      [SpeakSkill.vocabulary, SpeakSkill.grammar],
      ['question words', 'personal details'],
      [
        'Find who, where, and one detail.',
        'Connect the detail to the right person.',
      ],
    ),
    _t(
      'Listen for personal details',
      'identify names, countries, and simple personal information in speech',
      SpeakSkill.listening,
      [SpeakSkill.vocabulary, SpeakSkill.speaking],
      ['names', 'countries', 'numbers'],
      ['Identify the main detail.', 'Confirm one detail you heard.'],
    ),
    _t(
      'Introduce yourself',
      'say your name, origin, and one personal detail',
      SpeakSkill.speaking,
      [SpeakSkill.listening, SpeakSkill.vocabulary],
      ['être', 'venir de', 'question formation'],
      [
        'Say the introduction clearly.',
        'Ask or answer one follow-up question.',
      ],
    ),
    _t(
      'Learn café and food words',
      'recognize common café items, food, drinks, and numbers',
      SpeakSkill.vocabulary,
      [SpeakSkill.alphabet, SpeakSkill.listening],
      ['food and drinks', 'numbers', 'articles'],
      [
        'Recognize the target items.',
        'Choose the right word for a simple request.',
      ],
    ),
    _t(
      'Make a polite request',
      'form a short request for food or a drink',
      SpeakSkill.grammar,
      [SpeakSkill.vocabulary, SpeakSkill.roleplay],
      ['je voudrais', 'articles', 'question formation'],
      ['Build the request in the right order.', 'Use a polite closing.'],
    ),
    _t(
      'Read a simple menu',
      'find items, prices, and options in a short menu',
      SpeakSkill.reading,
      [SpeakSkill.vocabulary, SpeakSkill.grammar],
      ['prices', 'quantities', 'articles'],
      ['Find the requested item.', 'Read one price and one option.'],
    ),
    _t(
      'Listen for an order',
      'follow a short café order and catch the essential details',
      SpeakSkill.listening,
      [SpeakSkill.vocabulary, SpeakSkill.speaking],
      ['food and drinks', 'numbers', 'polite requests'],
      ['Identify the order.', 'Confirm the quantity or option.'],
    ),
    _t(
      'Order something simply',
      'order a food or drink and respond to one follow-up question',
      SpeakSkill.speaking,
      [SpeakSkill.listening, SpeakSkill.roleplay],
      ['je voudrais', 's\'il vous plaît', 'numbers'],
      ['Make the order clearly.', 'Respond to one choice question.'],
    ),
    _t(
      'Learn numbers and time',
      'recognize numbers, days, times, and simple schedules',
      SpeakSkill.vocabulary,
      [SpeakSkill.listening, SpeakSkill.reading],
      ['numbers', 'days', 'time expressions'],
      ['Recognize the target information.', 'Say one time or date accurately.'],
    ),
    _t(
      'Ask a clear question',
      'form a question about place, time, or a simple need',
      SpeakSkill.grammar,
      [SpeakSkill.vocabulary, SpeakSkill.speaking],
      ['est-ce que', 'question words', 'word order'],
      ['Choose the right question form.', 'Ask one complete question.'],
    ),
    _t(
      'Read a schedule or sign',
      'find a place, time, and action in a practical notice',
      SpeakSkill.reading,
      [SpeakSkill.vocabulary, SpeakSkill.listening],
      ['times', 'locations', 'imperatives'],
      ['Find the requested details.', 'Explain what the sign asks you to do.'],
    ),
    _t(
      'Listen for directions',
      'follow a short exchange about a route or appointment',
      SpeakSkill.listening,
      [SpeakSkill.vocabulary, SpeakSkill.speaking],
      ['directions', 'locations', 'time expressions'],
      ['Identify the destination.', 'Sequence two actions you heard.'],
    ),
    _t(
      'Use an everyday exchange',
      'combine first words, requests, directions, and repair strategies',
      SpeakSkill.speaking,
      [SpeakSkill.listening, SpeakSkill.review, SpeakSkill.roleplay],
      ['unit review', 'clarification phrases', 'polite requests'],
      [
        'Reach the practical goal.',
        'Repair one misunderstanding or ask for repetition.',
      ],
    ),
  ];

  /// Every twenty-session block has two deliberate production anchors. This
  /// prevents a learner who heavily weights listening, grammar, or writing
  /// from losing the dedicated speaking pathway entirely. The first anchor
  /// is a controlled speaking lesson; the second is a roleplay transfer.
  /// A1's first five sound foundations remain untouched.
  static _AdaptiveTemplate? _reservedSpeakingTemplate(
    List<_AdaptiveTemplate> templates,
    int sequence,
  ) {
    final position = ((sequence - 1) % adaptiveCourseBlockSize) + 1;
    final target = switch (position) {
      6 => SpeakSkill.speaking,
      16 => SpeakSkill.roleplay,
      _ => null,
    };
    if (target == null) return null;
    final candidates = templates
        .where((template) => template.primary == target)
        .toList(growable: false);
    if (candidates.isNotEmpty) {
      return candidates[((sequence - 1) ~/ adaptiveCourseBlockSize) %
          candidates.length];
    }
    throw StateError(
      'Adaptive course has no dedicated ${target.label} template for '
      'block position $position.',
    );
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
  }) {
    final target = focusSkills[(sequence - 4) % focusSkills.length];
    final rotation = (sequence - 4) ~/ focusSkills.length;
    final candidates = templates
        .where(
          (template) =>
              _matchesFocus(template.primary, target) ||
              (target == SpeakSkill.vocabulary &&
                  template.supporting.contains(target)),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw StateError(
        'Adaptive course has no template for focus ${target.label} '
        'at sequence $sequence.',
      );
    }
    // Every focus cycle gets a different competency where possible. The
    // second speaking cycle deliberately introduces roleplay so a learner
    // gets application practice early instead of a route of abstract drills.
    if (target == SpeakSkill.speaking && rotation.isOdd) {
      final roleplay = candidates.where(
        (template) => template.primary == SpeakSkill.roleplay,
      );
      if (roleplay.isNotEmpty) return roleplay.first;
    }
    return candidates[(rotation + cycle) % candidates.length];
  }

  static bool _matchesFocus(SpeakSkill primary, SpeakSkill focus) {
    if (primary == focus) return true;
    return switch (focus) {
      SpeakSkill.speaking =>
        primary == SpeakSkill.roleplay || primary == SpeakSkill.liaison,
      SpeakSkill.listening => primary == SpeakSkill.reading,
      SpeakSkill.writing => primary == SpeakSkill.connectors,
      _ => false,
    };
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

  static List<_AdaptiveTemplate> _templatesFor(String goal) {
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
      'Connect sound to meaning',
      'read and say essential words in the learner\'s target context',
      SpeakSkill.vocabulary,
      [SpeakSkill.alphabet, SpeakSkill.speaking],
      ['spelling and pronunciation'],
      ['Read the words.', 'Say them with a clear rhythm.'],
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
