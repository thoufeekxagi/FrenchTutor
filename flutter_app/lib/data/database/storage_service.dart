import 'dart:async';
import 'dart:convert';
import 'package:sqlite3/common.dart' hide Session;
import 'package:uuid/uuid.dart';
import '../../models/session.dart';
import '../../models/chat_message.dart';
import '../../models/note.dart';
import '../../services/sync_service.dart';

class StorageService {
  StorageService(this._db, [this._sync]) {
    _migrate();
  }

  final CommonDatabase _db;
  final SyncService? _sync;
  static const _uuid = Uuid();

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        summary TEXT,
        topic TEXT,
        vocabulary TEXT DEFAULT '[]',
        stage TEXT
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
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
    _db.execute(
      '''INSERT OR REPLACE INTO sessions (id, started_at, ended_at, summary, topic, vocabulary, stage)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        session.id,
        session.startedAt,
        session.endedAt,
        session.summary,
        session.topic,
        vocabJson,
        session.stage,
      ],
    );
  }

  List<Session> getAllSessions() {
    final rows = _db.select('SELECT * FROM sessions ORDER BY started_at DESC');
    return rows.map(_sessionFromRow).toList();
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
    _db.execute(
      'INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)',
      [sessionId, role, content],
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
    final row = _db.select(
      'SELECT * FROM notes WHERE id = ?',
      [rowId],
    ).first;
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
    _db.execute(
      "UPDATE notes SET deleted_at = datetime('now') WHERE id = ?",
      [id],
    );
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
      vocabulary: vocab,
      stage: row['stage'] as String?,
    );
  }
}
