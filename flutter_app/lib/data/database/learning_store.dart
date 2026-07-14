import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../models/daily_session.dart';
import '../../models/profile.dart';
import '../../models/srs_state.dart';
import 'app_migrations.dart';

class LessonProgress {
  LessonProgress({required this.lessonId, required this.status, this.score});
  final String lessonId;
  final String status;
  final double? score;
}

class HabitEntry {
  HabitEntry({required this.done, required this.minutes});
  final bool done;
  final int minutes;
}

class WritingSubmission {
  WritingSubmission({required this.taskId, required this.text, required this.feedback, required this.submittedAt});
  final String taskId;
  final String text;
  final String feedback;
  final String submittedAt;
}

class MistakeTag {
  MistakeTag({required this.tag, required this.description, required this.count, required this.resolved});
  final String tag;
  final String description;
  final int count;
  final bool resolved;
}

class DiaryEntry {
  DiaryEntry({required this.date, required this.stage, required this.summary});
  final String date;
  final String stage;
  final String summary;
}

const _uuid = Uuid();

class LearningStore {
  LearningStore(this._db) {
    runAppMigrations(_db);
    _migrateLegacy();
  }

  final Database _db;

  String _now() => DateTime.now().toUtc().toIso8601String();

  /// Legacy tables that predate the versioned migration system (see
  /// app_migrations.dart). Kept as-is for now; they already key on stable ids
  /// and will be folded into versioned migrations when they change shape.
  void _migrateLegacy() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS lesson_progress (
        lesson_id TEXT PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'not_started',
        score REAL
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS daily_activity (
        date TEXT NOT NULL,
        habit_id TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        minutes INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (date, habit_id)
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS writing_submissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id TEXT NOT NULL,
        text TEXT NOT NULL,
        feedback TEXT NOT NULL DEFAULT '',
        submitted_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS mistake_tags (
        tag TEXT PRIMARY KEY,
        description TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL DEFAULT 1,
        resolved INTEGER NOT NULL DEFAULT 0
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS session_diary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        stage TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // Profile — single local row, created on first read.
  // ---------------------------------------------------------------------------

  Profile profile() {
    final rows = _db.select('SELECT * FROM profiles WHERE deleted_at IS NULL LIMIT 1');
    if (rows.isNotEmpty) {
      final r = rows.first;
      final onboardedRaw = r['onboarded_at'] as String?;
      return Profile(
        id: r['id'] as String,
        goal: r['goal'] as String,
        level: r['level'] as String,
        sessionLength: r['session_length'] as String,
        reminderTime: r['reminder_time'] as String?,
        onboardedAt: onboardedRaw != null ? DateTime.tryParse(onboardedRaw) : null,
      );
    }
    final fresh = Profile(id: _uuid.v4());
    _db.execute(
      'INSERT INTO profiles (id, created_at, updated_at) VALUES (?, ?, ?)',
      [fresh.id, _now(), _now()],
    );
    return fresh;
  }

  void saveProfile(Profile p) {
    _db.execute('''
      UPDATE profiles SET goal = ?, level = ?, session_length = ?, reminder_time = ?,
        onboarded_at = ?, updated_at = ?
      WHERE id = ?
    ''', [p.goal, p.level, p.sessionLength, p.reminderTime, p.onboardedAt?.toIso8601String(), _now(), p.id]);
  }

  /// True until the very first card is ever graded — day-one learners get a
  /// gentler new-word budget.
  bool hasNoReviewHistory() {
    return (_db.select('SELECT COUNT(*) AS c FROM vocab_reviews').first['c'] as int) == 0;
  }

  // ---------------------------------------------------------------------------
  // SRS — current card state lives in vocab_cards; every grade also appends to
  // the immutable vocab_reviews log, which is the source of truth for pacing.
  // ---------------------------------------------------------------------------

  SRSState? srsState(String entryId) {
    final rows = _db.select(
        'SELECT * FROM vocab_cards WHERE entry_id = ? AND deleted_at IS NULL', [entryId]);
    if (rows.isEmpty) return null;
    return _srsFromRow(rows.first);
  }

  Map<String, SRSState> allSRSStates() {
    final rows = _db.select('SELECT * FROM vocab_cards WHERE deleted_at IS NULL');
    final map = <String, SRSState>{};
    for (final r in rows) {
      final s = _srsFromRow(r);
      map[s.entryId] = s;
    }
    return map;
  }

  void upsertSRS(SRSState state) {
    _db.execute('''
      INSERT INTO vocab_cards
        (id, entry_id, ease, interval_days, reps, due_at, introduced_on,
         last_reviewed_at, last_grade, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(entry_id) DO UPDATE SET
        ease = excluded.ease,
        interval_days = excluded.interval_days,
        reps = excluded.reps,
        due_at = excluded.due_at,
        introduced_on = COALESCE(vocab_cards.introduced_on, excluded.introduced_on),
        last_reviewed_at = excluded.last_reviewed_at,
        last_grade = excluded.last_grade,
        updated_at = excluded.updated_at
    ''', [
      _uuid.v4(),
      state.entryId,
      state.ease,
      state.intervalDays,
      state.reps,
      state.dueAt?.toIso8601String(),
      state.introducedOn,
      state.lastReviewedAt?.toIso8601String(),
      state.lastGrade?.name,
      _now(),
      _now(),
    ]);
  }

  /// Append one review to the immutable log.
  void logReview({
    required String entryId,
    required SRSGrade grade,
    required SRSResponseType responseType,
    String? sessionId,
  }) {
    _db.execute('''
      INSERT INTO vocab_reviews (id, entry_id, grade, response_type, session_id, reviewed_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [_uuid.v4(), entryId, grade.name, responseType.name, sessionId, _now(), _now()]);
  }

  /// Cards first graded today — counted from the explicit introduced_on column,
  /// never inferred from due dates.
  int newEntriesIntroducedToday() {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM vocab_cards WHERE introduced_on = ? AND deleted_at IS NULL',
      [dayString(DateTime.now())],
    );
    return rows.first['c'] as int;
  }

  /// Entries reviewed today with their latest grade — feeds progress evidence
  /// ("this week you can now…") and same-session again-loops.
  List<({String entryId, SRSGrade grade, DateTime reviewedAt})> reviewsOn(DateTime day) {
    final rows = _db.select(
      "SELECT entry_id, grade, reviewed_at FROM vocab_reviews WHERE date(reviewed_at) = date(?) ORDER BY reviewed_at",
      [day.toUtc().toIso8601String()],
    );
    return rows
        .map((r) => (
              entryId: r['entry_id'] as String,
              grade: SRSGrade.values.asNameMap()[r['grade'] as String] ?? SRSGrade.good,
              reviewedAt: DateTime.parse(r['reviewed_at'] as String),
            ))
        .toList();
  }

  /// Distinct entries recalled successfully (good/easy) since [since] —
  /// the evidence behind "this week you can now…" progress framing.
  List<String> entriesRecalledSince(DateTime since) {
    final rows = _db.select(
      "SELECT DISTINCT entry_id FROM vocab_reviews WHERE reviewed_at >= ? AND grade IN ('good', 'easy')",
      [since.toUtc().toIso8601String()],
    );
    return rows.map((r) => r['entry_id'] as String).toList();
  }

  // ---------------------------------------------------------------------------
  // Daily Path persistence — one row per local date, updated on every
  // meaningful transition so the learner can always resume exactly in place.
  // ---------------------------------------------------------------------------

  DailySession dailySession({DateTime? on}) {
    final date = dayString(on ?? DateTime.now());
    final rows = _db.select(
        'SELECT * FROM daily_sessions WHERE local_date = ? AND deleted_at IS NULL', [date]);
    if (rows.isNotEmpty) return _dailyFromRow(rows.first);

    final session = DailySession(id: _uuid.v4(), localDate: date);
    _db.execute('''
      INSERT INTO daily_sessions (id, local_date, stages_json, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    ''', [session.id, date, session.stagesToJson(), _now(), _now()]);
    return session;
  }

  void saveDailySession(DailySession session) {
    _db.execute('''
      UPDATE daily_sessions SET
        planned_length = ?, current_stage = ?, current_item_index = ?,
        stages_json = ?, vocab_entry_ids_json = ?, grammar_lesson_id = ?,
        reading_passage_json = ?, started_at = ?, completed_at = ?, updated_at = ?
      WHERE id = ?
    ''', [
      session.plannedLength,
      session.currentStage?.name,
      session.currentItemIndex,
      session.stagesToJson(),
      session.vocabEntryIds != null ? jsonEncode(session.vocabEntryIds) : null,
      session.grammarLessonId,
      session.readingPassageJson != null ? jsonEncode(session.readingPassageJson) : null,
      session.startedAt?.toIso8601String(),
      session.completedAt?.toIso8601String(),
      _now(),
      session.id,
    ]);
  }

  // ---------------------------------------------------------------------------
  // AI sessions — real timestamps, utterance counts, honest end reasons.
  // ---------------------------------------------------------------------------

  String startAiSession({String? dailySessionId, String? stage, String? topic}) {
    final id = _uuid.v4();
    _db.execute('''
      INSERT INTO ai_sessions (id, daily_session_id, stage, topic, connected_at, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [id, dailySessionId, stage, topic, _now(), _now(), _now()]);
    return id;
  }

  void endAiSession(
    String id, {
    required String endedReason,
    required int learnerUtteranceCount,
    String? transcriptJson,
  }) {
    _db.execute('''
      UPDATE ai_sessions SET ended_at = ?, ended_reason = ?, learner_utterance_count = ?,
        transcript_json = COALESCE(?, transcript_json), updated_at = ?
      WHERE id = ?
    ''', [_now(), endedReason, learnerUtteranceCount, transcriptJson, _now(), id]);

    // Credit ledger entry from real timestamps (advisory until server-metered).
    final rows = _db.select('SELECT connected_at, ended_at FROM ai_sessions WHERE id = ?', [id]);
    if (rows.isNotEmpty && rows.first['connected_at'] != null && rows.first['ended_at'] != null) {
      final seconds = DateTime.parse(rows.first['ended_at'] as String)
          .difference(DateTime.parse(rows.first['connected_at'] as String))
          .inSeconds;
      if (seconds > 0) {
        _db.execute('''
          INSERT INTO credit_usage (id, local_date, seconds_used, ai_session_id, created_at)
          VALUES (?, ?, ?, ?, ?)
        ''', [_uuid.v4(), dayString(DateTime.now()), seconds, id, _now()]);
      }
    }
  }

  int aiSecondsUsedToday() {
    final rows = _db.select(
      'SELECT COALESCE(SUM(seconds_used), 0) AS s FROM credit_usage WHERE local_date = ?',
      [dayString(DateTime.now())],
    );
    return rows.first['s'] as int;
  }

  // --- Lesson progress ---

  LessonProgress lessonStatus(String lessonId) {
    final rows = _db.select('SELECT * FROM lesson_progress WHERE lesson_id = ?', [lessonId]);
    if (rows.isEmpty) return LessonProgress(lessonId: lessonId, status: 'not_started');
    final r = rows.first;
    return LessonProgress(
      lessonId: r['lesson_id'] as String,
      status: r['status'] as String,
      score: r['score'] as double?,
    );
  }

  void setLessonStatus(String lessonId, String status, {double? score}) {
    _db.execute(
      '''INSERT OR REPLACE INTO lesson_progress (lesson_id, status, score)
         VALUES (?, ?, ?)''',
      [lessonId, status, score],
    );
  }

  Map<String, LessonProgress> allLessonProgress() {
    final rows = _db.select('SELECT * FROM lesson_progress');
    final map = <String, LessonProgress>{};
    for (final r in rows) {
      final lp = LessonProgress(
        lessonId: r['lesson_id'] as String,
        status: r['status'] as String,
        score: r['score'] as double?,
      );
      map[lp.lessonId] = lp;
    }
    return map;
  }

  // --- Daily activity ---

  /// Minutes ACCUMULATE across a day (a second session adds, never replaces).
  void markHabit(String habitId, {bool done = true, int minutes = 0}) {
    final today = dayString(DateTime.now());
    _db.execute('''
      INSERT INTO daily_activity (date, habit_id, done, minutes)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(date, habit_id) DO UPDATE SET
        done = MAX(daily_activity.done, excluded.done),
        minutes = daily_activity.minutes + excluded.minutes
    ''', [today, habitId, done ? 1 : 0, minutes]);
  }

  Map<String, HabitEntry> habits({DateTime? on}) {
    final date = dayString(on ?? DateTime.now());
    final rows = _db.select('SELECT * FROM daily_activity WHERE date = ?', [date]);
    final map = <String, HabitEntry>{};
    for (final r in rows) {
      map[r['habit_id'] as String] = HabitEntry(
        done: (r['done'] as int) == 1,
        minutes: r['minutes'] as int,
      );
    }
    return map;
  }

  List<String> activeDays() {
    final rows = _db.select('SELECT DISTINCT date FROM daily_activity WHERE done = 1 ORDER BY date DESC');
    return rows.map((r) => r['date'] as String).toList();
  }

  // --- Writing submissions ---

  void saveSubmission({required String taskId, required String text, String feedback = ''}) {
    _db.execute(
      'INSERT INTO writing_submissions (task_id, text, feedback) VALUES (?, ?, ?)',
      [taskId, text, feedback],
    );
  }

  List<WritingSubmission> submissions() {
    final rows = _db.select('SELECT * FROM writing_submissions ORDER BY submitted_at DESC');
    return rows
        .map((r) => WritingSubmission(
              taskId: r['task_id'] as String,
              text: r['text'] as String,
              feedback: r['feedback'] as String,
              submittedAt: r['submitted_at'] as String,
            ))
        .toList();
  }

  // --- Mistake tags ---

  void logMistake({required String tag, required String description}) {
    _db.execute(
      '''INSERT INTO mistake_tags (tag, description, count) VALUES (?, ?, 1)
         ON CONFLICT(tag) DO UPDATE SET count = count + 1, description = excluded.description''',
      [tag, description],
    );
  }

  List<MistakeTag> topMistakeTags({int limit = 5}) {
    final rows = _db.select(
      'SELECT * FROM mistake_tags WHERE resolved = 0 ORDER BY count DESC LIMIT ?',
      [limit],
    );
    return rows
        .map((r) => MistakeTag(
              tag: r['tag'] as String,
              description: r['description'] as String,
              count: r['count'] as int,
              resolved: (r['resolved'] as int) == 1,
            ))
        .toList();
  }

  void resolveMistakeTag(String tag) {
    _db.execute('UPDATE mistake_tags SET resolved = 1 WHERE tag = ?', [tag]);
  }

  // --- Session diary ---

  void saveDiaryEntry({required String stage, required String summary}) {
    final today = dayString(DateTime.now());
    _db.execute(
      'INSERT INTO session_diary (date, stage, summary) VALUES (?, ?, ?)',
      [today, stage, summary],
    );
  }

  List<DiaryEntry> recentDiaryEntries({int limit = 10}) {
    final rows = _db.select('SELECT * FROM session_diary ORDER BY id DESC LIMIT ?', [limit]);
    return rows
        .map((r) => DiaryEntry(
              date: r['date'] as String,
              stage: r['stage'] as String,
              summary: r['summary'] as String,
            ))
        .toList();
  }

  // --- Helpers ---

  String dayString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  SRSState _srsFromRow(Row row) {
    DateTime? parseDate(Object? raw) =>
        raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
    return SRSState(
      entryId: row['entry_id'] as String,
      ease: (row['ease'] as num).toDouble(),
      intervalDays: (row['interval_days'] as num).toDouble(),
      reps: row['reps'] as int,
      dueAt: parseDate(row['due_at']),
      lastGrade: SRSGrade.values.asNameMap()[row['last_grade'] as String?],
      introducedOn: row['introduced_on'] as String?,
      lastReviewedAt: parseDate(row['last_reviewed_at']),
    );
  }

  DailySession _dailyFromRow(Row row) {
    DateTime? parseDate(Object? raw) =>
        raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
    return DailySession(
      id: row['id'] as String,
      localDate: row['local_date'] as String,
      plannedLength: row['planned_length'] as String,
      currentStage: PathwayStage.values.asNameMap()[row['current_stage'] as String?],
      currentItemIndex: row['current_item_index'] as int,
      stages: DailySession.stagesFromJson(row['stages_json'] as String),
      vocabEntryIds: row['vocab_entry_ids_json'] != null
          ? (jsonDecode(row['vocab_entry_ids_json'] as String) as List).cast<String>()
          : null,
      grammarLessonId: row['grammar_lesson_id'] as String?,
      readingPassageJson: row['reading_passage_json'] != null
          ? (jsonDecode(row['reading_passage_json'] as String) as Map).cast<String, dynamic>()
          : null,
      startedAt: parseDate(row['started_at']),
      completedAt: parseDate(row['completed_at']),
    );
  }
}
