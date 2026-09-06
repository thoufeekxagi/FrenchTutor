import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/grammar_course.dart';
import '../../models/grammar_course_v2.dart';
import '../../services/sync_service.dart';
import 'app_migrations.dart';

const _grammarCourseUuid = Uuid();

/// Local cache for complete Grammar sessions. A session is the persistence
/// unit; its 4–5 steps are never promoted to individual library rows.
class GrammarCourseLessonStore {
  GrammarCourseLessonStore(
    this._db, {
    SyncService? sync,
    String? Function()? currentUserId,
  }) : _sync = sync,
       _userId = currentUserId {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;
  final String? Function()? _userId;

  List<GrammarCourseSession> list({
    GrammarV2Mode? mode,
    String? level,
    String? tense,
  }) {
    final where = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    final uid = _userId?.call();
    if (uid == null) {
      where.add('user_id IS NULL');
    } else {
      where.add('user_id = ?');
      args.add(uid);
    }
    if (mode != null) {
      where.add('mode = ?');
      args.add(mode.name);
    }
    if (level != null) {
      where.add('level_band = ?');
      args.add(level);
    }
    if (tense != null) {
      where.add('tense = ?');
      args.add(tense);
    }
    final rows = _db.select('''
      SELECT session_json
      FROM grammar_course_sessions
      WHERE ${where.join(' AND ')}
      ORDER BY created_at ASC
    ''', args);
    final sessions = <GrammarCourseSession>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['session_json'] as String);
        if (decoded is! Map) continue;
        sessions.add(
          GrammarCourseValidator.validate(
            GrammarCourseSession.fromJson(decoded.cast<String, dynamic>()),
          ),
        );
      } catch (_) {
        // A bad generated row never removes the authored starter sessions.
      }
    }
    return sessions;
  }

  bool insertGenerated(GrammarCourseSession session) {
    final validated = GrammarCourseValidator.validate(
      session.copyWith(source: 'generated'),
    );
    final fingerprint = grammarCourseFingerprint(validated);
    final uid = _userId?.call();
    final duplicate = uid == null
        ? _db.select(
            'SELECT 1 FROM grammar_course_sessions '
            'WHERE user_id IS NULL AND fingerprint = ? AND deleted_at IS NULL LIMIT 1',
            [fingerprint],
          )
        : _db.select(
            'SELECT 1 FROM grammar_course_sessions '
            'WHERE user_id = ? AND fingerprint = ? AND deleted_at IS NULL LIMIT 1',
            [uid, fingerprint],
          );
    if (duplicate.isNotEmpty) return false;

    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO grammar_course_sessions
         (id, user_id, source, mode, tense, level_band, title, fingerprint,
          session_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        validated.id,
        uid,
        validated.source,
        validated.mode.name,
        validated.tense,
        validated.level,
        validated.title,
        fingerprint,
        jsonEncode(validated.toJson()),
        now,
        now,
      ],
    );
    unawaited(_sync?.syncGrammarCourseSession(validated));
    return true;
  }

  void upsertFromRemote({
    required String id,
    required String source,
    required String mode,
    required String tense,
    required String levelBand,
    required String title,
    required String fingerprint,
    required String sessionJson,
    required String createdAt,
    required String updatedAt,
  }) {
    final byFingerprint = _db.select(
      'SELECT id FROM grammar_course_sessions '
      'WHERE user_id = ? AND fingerprint = ? AND deleted_at IS NULL LIMIT 1',
      [_userId?.call(), fingerprint],
    );
    if (byFingerprint.isNotEmpty && byFingerprint.first['id'] != id) return;
    _db.execute(
      '''INSERT INTO grammar_course_sessions
         (id, user_id, source, mode, tense, level_band, title, fingerprint,
          session_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           source = excluded.source,
           mode = excluded.mode,
           tense = excluded.tense,
           level_band = excluded.level_band,
           title = excluded.title,
           fingerprint = excluded.fingerprint,
           session_json = excluded.session_json,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > grammar_course_sessions.updated_at''',
      [
        id,
        _userId?.call(),
        source,
        mode,
        tense,
        levelBand,
        title,
        fingerprint,
        sessionJson,
        createdAt,
        updatedAt,
      ],
    );
  }

  static String newId() => _grammarCourseUuid.v4();
}
