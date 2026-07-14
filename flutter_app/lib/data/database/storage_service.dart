import 'dart:convert';
import 'package:sqlite3/sqlite3.dart' hide Session;
import '../../models/session.dart';
import '../../models/chat_message.dart';
import '../../models/note.dart';

class StorageService {
  StorageService(this._db) {
    _migrate();
  }

  final Database _db;

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
    _db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tag TEXT,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        times_shown INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  void saveSession(Session session) {
    final vocabJson = jsonEncode(session.vocabulary);
    _db.execute(
      '''INSERT OR REPLACE INTO sessions (id, started_at, ended_at, summary, topic, vocabulary, stage)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [session.id, session.startedAt, session.endedAt, session.summary, session.topic, vocabJson, session.stage],
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

  void saveMessage({required String sessionId, required String role, required String content}) {
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
        .map((r) => ChatMessage(
              id: r['id'].toString(),
              role: r['role'] as String,
              content: r['content'] as String,
            ))
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
  int saveNote({int? id, String? tag, required String text}) {
    if (id != null) {
      _db.execute(
        "UPDATE notes SET tag = ?, text = ?, updated_at = datetime('now') WHERE id = ?",
        [tag, text, id],
      );
      return id;
    }
    _db.execute('INSERT INTO notes (tag, text) VALUES (?, ?)', [tag, text]);
    return _db.lastInsertRowId;
  }

  List<Note> getAllNotes() {
    final rows = _db.select('SELECT * FROM notes ORDER BY updated_at DESC');
    return rows
        .map((r) => Note(
              id: r['id'] as int,
              tag: r['tag'] as String?,
              text: r['text'] as String,
              createdAt: r['created_at'] as String,
              updatedAt: r['updated_at'] as String,
              timesShown: r['times_shown'] as int,
            ))
        .toList();
  }

  void deleteNote(int id) {
    _db.execute('DELETE FROM notes WHERE id = ?', [id]);
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
