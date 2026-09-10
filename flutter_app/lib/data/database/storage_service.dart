import 'dart:async';
import 'dart:convert';
import 'package:sqlite3/common.dart' hide Session;
import 'package:uuid/uuid.dart';
import '../../models/session.dart';
import '../../models/chat_message.dart';
import '../../models/note.dart';
import '../../services/sync_service.dart';
import '../../services/review_context_cache_service.dart';

class StorageService {
  StorageService(this._db, [this._sync]) {
    _migrate();
  }

  final CommonDatabase _db;
  final SyncService? _sync;
  static const _uuid = Uuid();

  void _migrate() {
    // Full shape kept in sync with `_migrationV17` in app_migrations.dart —
    // whichever of the two runs first "wins" and the other is a no-op, same
    // dual-definition pattern `notes`/`_migrationV15` already uses.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        summary TEXT,
        topic TEXT,
        content_key TEXT,
        vocabulary TEXT DEFAULT '[]',
        stage TEXT,
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        deleted_at TEXT
      )
    ''');
    final hasContentKey = _db
        .select('PRAGMA table_info(sessions)')
        .any((row) => row['name'] == 'content_key');
    if (!hasContentKey) {
      _db.execute('ALTER TABLE sessions ADD COLUMN content_key TEXT');
    }
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_content_key ON sessions (content_key)',
    );
    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        user_id TEXT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_uuid ON messages (uuid) WHERE uuid IS NOT NULL',
    );
    // Full shape kept in sync with `_migrationV15` in app_migrations.dart —
    // whichever of the two runs first "wins" and the other is a no-op, since
    // provider-resolution order isn't guaranteed (see that migration's doc
    // comment).
    _db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        user_id TEXT,
        tag TEXT,
        text TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'user',
        session_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        times_shown INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_uuid ON notes (uuid) WHERE uuid IS NOT NULL',
    );
  }

  void saveSession(Session session) {
    final vocabJson = jsonEncode(session.vocabulary);
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT OR REPLACE INTO sessions
         (id, started_at, ended_at, summary, topic, content_key, vocabulary, stage, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        session.id,
        session.startedAt,
        session.endedAt,
        session.summary,
        session.topic,
        session.contentKey,
        vocabJson,
        session.stage,
        now,
      ],
    );
    // Every completed practice session — this is the exact data
    // streak/momentum/"this week's practice" reads (DailyGoalService), so
    // losing this on reinstall was the "starts from zero" bug.
    unawaited(_sync?.syncSession(session, updatedAt: now));
    // Review indexing is additive and deliberately not awaited. The session
    // row above is already durable before this optimization starts.
    if (session.endedAt != null && session.endedAt!.isNotEmpty) {
      _saveCourseMaterialSnapshotIfNeeded(session);
      ReviewContextCacheService.schedule(_db);
    }
  }

  /// A typed Writing/Grammar/Vocabulary Course screen may finish without a
  /// conversational transcript.  Persist one compact material snapshot next
  /// to the completion row so Review/Warm-up can still recover the actual
  /// generated lesson on a later install, even if the adaptive artifact has
  /// not hydrated yet. Conversational sessions already have turns and do not
  /// get a duplicate snapshot.
  void _saveCourseMaterialSnapshotIfNeeded(Session session) {
    final key = session.contentKey?.trim() ?? '';
    if (key.isEmpty || getSessionMessages(sessionId: session.id).isNotEmpty) {
      return;
    }
    final details = getSessionReviewDetails(
      sessionId: session.id,
      contentKey: key,
    );
    if (details.isEmpty) return;
    _saveBoundedCourseMaterial(
      sessionId: session.id,
      material: details.join('\n'),
    );
  }

  List<Session> getAllSessions() {
    final rows = _db.select('SELECT * FROM sessions ORDER BY started_at DESC');
    return rows.map(_sessionFromRow).toList();
  }

  /// Stable course items completed by this learner. Legacy sessions without
  /// a content key remain available through [getAllSessions] for history and
  /// the roadmap's backwards-compatible count fallback.
  Set<String> completedContentKeys() {
    final rows = _db.select(
      'SELECT DISTINCT content_key FROM sessions WHERE content_key IS NOT NULL AND content_key != ? AND deleted_at IS NULL',
      [''],
    );
    return rows.map((row) => row['content_key'] as String).toSet();
  }

  /// Records a course completion once, even when a learner completes several
  /// supporting activities before returning to the course session screen.
  void markCourseSessionCompleted({
    required String contentKey,
    required String topic,
    required String stage,
    String? lessonMaterial,
  }) {
    final existing = _db.select(
      'SELECT 1 FROM sessions WHERE content_key = ? AND deleted_at IS NULL LIMIT 1',
      [contentKey],
    );
    if (existing.isNotEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final session = Session(
      id: _uuid.v4(),
      startedAt: now,
      endedAt: now,
      summary: 'Completed the course session: $topic',
      topic: topic,
      contentKey: contentKey,
      stage: stage,
    );
    saveSession(session);
    // The roadmap already has the generated artifact in memory. Keep a
    // bounded fallback beside the completion row in case the local adaptive
    // artifact is still waiting on its own sync transaction.
    if (lessonMaterial != null &&
        lessonMaterial.trim().isNotEmpty &&
        getSessionMessages(sessionId: session.id).isEmpty) {
      _saveBoundedCourseMaterial(
        sessionId: session.id,
        material: lessonMaterial,
      );
      ReviewContextCacheService.schedule(_db);
    }
  }

  void _saveBoundedCourseMaterial({
    required String sessionId,
    required String material,
  }) {
    final normalized = material.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return;
    final bounded = normalized.length <= 1800
        ? normalized
        : '${normalized.substring(0, 1799).trimRight()}…';
    saveMessage(
      sessionId: sessionId,
      role: 'assistant',
      content: 'Course lesson material:\n$bounded',
    );
  }

  Session? mostRecentSession({required String stage}) {
    final rows = _db.select(
      'SELECT * FROM sessions WHERE stage = ? ORDER BY started_at DESC LIMIT 1',
      [stage],
    );
    return rows.isEmpty ? null : _sessionFromRow(rows.first);
  }

  void saveMessage({
    required String sessionId,
    required String role,
    required String content,
  }) {
    final uuid = _uuid.v4();
    _db.execute(
      'INSERT INTO messages (uuid, session_id, role, content) VALUES (?, ?, ?, ?)',
      [uuid, sessionId, role, content],
    );
    unawaited(
      _sync?.syncMessage(
        uuid: uuid,
        sessionId: sessionId,
        role: role,
        content: content,
      ),
    );
  }

  List<ChatMessage> getSessionMessages({required String sessionId}) {
    final rows = _db.select(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY id ASC',
      [sessionId],
    );
    return rows
        .map(
          (r) => ChatMessage(
            id: r['id'].toString(),
            role: r['role'] as String,
            content: r['content'] as String,
          ),
        )
        .toList();
  }

  /// Returns a bounded, learner-facing description of the material that was
  /// actually practised in a session.  A generic Course completion row only
  /// contains its heading, so Review also joins the persisted adaptive lesson
  /// artifact and any saved learner/tutor turns here.
  ///
  /// This is deliberately read-only and best-effort: older installs may not
  /// have the adaptive table or one of its newer columns yet.  In that case
  /// the normal session summary still remains available to Review.
  List<String> getSessionReviewDetails({
    required String sessionId,
    String? contentKey,
  }) {
    final details = <String>[];
    void add(String value, {int max = 420}) {
      final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty || details.contains(clean)) return;
      details.add(
        clean.length <= max
            ? clean
            : '${clean.substring(0, max - 1).trimRight()}…',
      );
    }

    for (final message in getSessionMessages(sessionId: sessionId).take(12)) {
      add(
        '${message.isUser ? 'Learner' : 'Tutor'}: ${message.content}',
        max: 320,
      );
    }

    final key = contentKey?.trim() ?? '';
    if (key.isEmpty) return details;
    try {
      final rows = _db.select(
        '''SELECT title, subtitle, context, competency,
                  grammar_focus_json, success_criteria_json,
                  target_phrases_json, artifact_json
           FROM adaptive_course_sessions
           WHERE content_key = ? AND deleted_at IS NULL
           ORDER BY updated_at DESC LIMIT 1''',
        [key],
      );
      if (rows.isEmpty) return details;
      final row = rows.first;
      add('Lesson: ${row['title'] ?? ''}');
      add('Context: ${row['context'] ?? row['subtitle'] ?? ''}');
      add('Competency: ${row['competency'] ?? ''}');
      add(
        'Grammar focus: ${_reviewJsonList(row['grammar_focus_json']).join('; ')}',
      );
      add(
        'Success criteria: ${_reviewJsonList(row['success_criteria_json']).join('; ')}',
      );
      add(
        'Target language: ${_reviewJsonList(row['target_phrases_json']).join('; ')}',
      );
      final artifact = _reviewJsonMap(row['artifact_json']);
      if (artifact.isNotEmpty) {
        // Keep the complete generated payload available to the saved review,
        // but bound it so a large listening deck can never bloat the screen.
        add('Generated activity: ${jsonEncode(artifact)}', max: 1400);
      }
    } catch (_) {
      // Course artifacts are optional for legacy and partially migrated DBs.
    }
    return details;
  }

  List<String> _reviewJsonList(Object? raw) {
    if (raw is List) return raw.map((value) => value.toString()).toList();
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.map((value) => value.toString()).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _reviewJsonMap(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  void deleteSession(String id) {
    _db.execute('DELETE FROM messages WHERE session_id = ?', [id]);
    _db.execute('DELETE FROM sessions WHERE id = ?', [id]);
  }

  /// Creates a new note when [id] is null, or updates the existing row (text + updated_at)
  /// when [id] is given — returns the row's id either way. Callers doing incremental autosave
  /// (the floating notetaker) MUST pass back the id they got from the previous call, or every
  /// autosave tick creates a new duplicate row instead of evolving one draft.
  ///
  /// [source] is 'user' for anything typed by the learner, or 'ai' for an
  /// auto-generated recap of a live session's new vocabulary (see
  /// `LessonAgentService.summarizeSessionForNotes`) — both live in this same
  /// table and list. Every save also pushes to Supabase (best-effort), so a
  /// legacy row with no `uuid` yet gets one assigned here on its first
  /// post-migration save, rather than staying local-only forever.
  int saveNote({
    int? id,
    String? tag,
    required String text,
    String source = 'user',
    String? sessionId,
  }) {
    final freshUuid = _uuid.v4();
    int rowId;
    if (id != null) {
      _db.execute(
        '''UPDATE notes SET tag = ?, text = ?, source = ?, session_id = ?,
           uuid = COALESCE(uuid, ?), updated_at = datetime('now') WHERE id = ?''',
        [tag, text, source, sessionId, freshUuid, id],
      );
      rowId = id;
    } else {
      _db.execute(
        'INSERT INTO notes (uuid, tag, text, source, session_id) VALUES (?, ?, ?, ?, ?)',
        [freshUuid, tag, text, source, sessionId],
      );
      rowId = _db.lastInsertRowId;
    }
    final row = _db.select('SELECT * FROM notes WHERE id = ?', [rowId]).first;
    unawaited(_sync?.syncNote(_noteFromRow(row)));
    return rowId;
  }

  Note _noteFromRow(Row r) => Note(
    id: r['id'] as int,
    uuid: r['uuid'] as String?,
    tag: r['tag'] as String?,
    text: r['text'] as String,
    source: r['source'] as String? ?? 'user',
    sessionId: r['session_id'] as String?,
    createdAt: r['created_at'] as String,
    updatedAt: r['updated_at'] as String,
    timesShown: r['times_shown'] as int,
  );

  List<Note> getAllNotes() {
    final rows = _db.select(
      'SELECT * FROM notes WHERE deleted_at IS NULL ORDER BY updated_at DESC',
    );
    return rows.map(_noteFromRow).toList();
  }

  void deleteNote(int id) {
    final rows = _db.select('SELECT uuid FROM notes WHERE id = ?', [id]);
    final uuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
    _db.execute("UPDATE notes SET deleted_at = datetime('now') WHERE id = ?", [
      id,
    ]);
    if (uuid != null) unawaited(_sync?.deleteNote(uuid));
  }

  Session _sessionFromRow(Row row) {
    List<String> vocab = [];
    final raw = row['vocabulary'];
    if (raw != null && raw is String && raw.isNotEmpty) {
      vocab = List<String>.from(jsonDecode(raw));
    }
    return Session(
      id: row['id'] as String,
      startedAt: row['started_at'] as String,
      endedAt: row['ended_at'] as String?,
      summary: row['summary'] as String?,
      topic: row['topic'] as String?,
      contentKey: row['content_key'] as String?,
      vocabulary: vocab,
      stage: row['stage'] as String?,
    );
  }
}
