import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/session.dart';

class StorageService {
  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'french_tutor.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            summary TEXT,
            topic TEXT,
            vocabulary TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> saveSession(Session session) async {
    final db = await _getDb();
    await db.insert(
      'sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveMessage(String sessionId, String role, String content) async {
    final db = await _getDb();
    await db.insert('messages', {
      'session_id': sessionId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Session>> getAllSessions() async {
    final db = await _getDb();
    final maps = await db.query('sessions', orderBy: 'started_at DESC');
    return maps.map((m) => Session.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId) async {
    final db = await _getDb();
    final maps = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return maps;
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await _getDb();
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  void dispose() {
    _db?.close();
  }
}
