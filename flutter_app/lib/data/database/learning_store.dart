import 'package:sqlite3/sqlite3.dart';
import '../../models/srs_state.dart';

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

class LearningStore {
  LearningStore(this._db) {
    _db.execute('PRAGMA journal_mode=WAL');
    _migrate();
  }

  final Database _db;

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS vocab_srs (
        entry_id TEXT PRIMARY KEY,
        ease REAL NOT NULL DEFAULT 2.5,
        interval_days REAL NOT NULL DEFAULT 0,
        reps INTEGER NOT NULL DEFAULT 0,
        due_at TEXT,
        last_grade INTEGER
      )
    ''');
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

  // --- SRS ---

  SRSState? srsState(String entryId) {
    final rows = _db.select('SELECT * FROM vocab_srs WHERE entry_id = ?', [entryId]);
    if (rows.isEmpty) return null;
    return _srsFromRow(rows.first);
  }

  Map<String, SRSState> allSRSStates() {
    final rows = _db.select('SELECT * FROM vocab_srs');
    final map = <String, SRSState>{};
    for (final r in rows) {
      final s = _srsFromRow(r);
      map[s.entryId] = s;
    }
    return map;
  }

  void upsertSRS(SRSState state) {
    _db.execute(
      '''INSERT OR REPLACE INTO vocab_srs (entry_id, ease, interval_days, reps, due_at, last_grade)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [state.entryId, state.ease, state.intervalDays, state.reps, state.dueAt?.toIso8601String(), state.lastGrade],
    );
  }

  int newEntriesIntroducedToday() {
    final today = dayString(DateTime.now());
    final rows = _db.select(
      "SELECT COUNT(*) AS c FROM vocab_srs WHERE date(due_at) >= ? AND reps = 1",
      [today],
    );
    return rows.first['c'] as int;
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

  void markHabit(String habitId, {bool done = true, int minutes = 0}) {
    final today = dayString(DateTime.now());
    _db.execute(
      '''INSERT OR REPLACE INTO daily_activity (date, habit_id, done, minutes)
         VALUES (?, ?, ?, ?)''',
      [today, habitId, done ? 1 : 0, minutes],
    );
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
    DateTime? dueAt;
    final raw = row['due_at'];
    if (raw != null && raw is String && raw.isNotEmpty) {
      dueAt = DateTime.tryParse(raw);
    }
    return SRSState(
      entryId: row['entry_id'] as String,
      ease: (row['ease'] as num).toDouble(),
      intervalDays: (row['interval_days'] as num).toDouble(),
      reps: row['reps'] as int,
      dueAt: dueAt,
      lastGrade: row['last_grade'] as int?,
    );
  }
}
