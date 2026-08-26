import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/speaking_course.dart';
import '../../services/sync_service.dart';
import 'app_migrations.dart';
import 'speaking_lesson_codec.dart';

const _speakingUuid = Uuid();

/// Local cache and write buffer for the shared Speaking catalog.
///
/// Both bundled/default lessons and validated AI lessons use the same durable
/// row shape. The source column lets the UI distinguish the app's starter
/// catalog from generated lessons without giving either path a second content
/// contract.
class SpeakingLessonStore {
  SpeakingLessonStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  List<SpeakingCourseLesson> list({
    SpeakingCourseMode? mode,
    String? level,
    String? source,
  }) {
    final where = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (mode != null) {
      where.add('mode = ?');
      args.add(mode.name);
    }
    if (level != null) {
      where.add('level_band = ?');
      args.add(level);
    }
    if (source != null) {
      where.add('source = ?');
      args.add(source);
    }
    final rows = _db.select('''SELECT lesson_json FROM speaking_lessons
         WHERE ${where.join(' AND ')}
         ORDER BY created_at ASC''', args);
    final lessons = <SpeakingCourseLesson>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row['lesson_json'] as String);
        if (json is Map) {
          lessons.add(
            speakingCourseLessonFromJson(json.cast<String, dynamic>()),
          );
        }
      } catch (_) {
        // A malformed remote row must not take down the entire Speaking tab.
        // It remains in Supabase for diagnosis and is ignored locally.
      }
    }
    return lessons;
  }

  /// Writes a validated generated lesson locally first, then queues its
  /// public Supabase write. The local row is what makes the UI instant.
  bool insertGenerated(SpeakingCourseLesson lesson) {
    final fingerprint = speakingLessonFingerprint(lesson);
    final duplicate = _db.select(
      'SELECT 1 FROM speaking_lessons WHERE fingerprint = ? AND deleted_at IS NULL LIMIT 1',
      [fingerprint],
    );
    if (duplicate.isNotEmpty) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    final json = jsonEncode(speakingCourseLessonToJson(lesson));
    _db.execute(
      '''INSERT INTO speaking_lessons
         (id, source, mode, level_band, title, fingerprint, lesson_json,
          created_at, updated_at)
         VALUES (?, 'generated', ?, ?, ?, ?, ?, ?, ?)''',
      [
        lesson.id,
        lesson.mode.name,
        lesson.level,
        lesson.title,
        fingerprint,
        json,
        now,
        now,
      ],
    );
    unawaited(_sync?.syncSpeakingLesson(lesson));
    return true;
  }

  /// Upserts one public row pulled during account hydration. Duplicate
  /// fingerprints are intentionally ignored: the first stable ID wins, so a
  /// repeated generator output cannot create duplicate cards on reinstall.
  void upsertFromRemote({
    required String id,
    required String source,
    required String mode,
    required String levelBand,
    required String title,
    required String fingerprint,
    required String lessonJson,
    required String createdAt,
    required String updatedAt,
  }) {
    final byFingerprint = _db.select(
      'SELECT id FROM speaking_lessons WHERE fingerprint = ? AND deleted_at IS NULL LIMIT 1',
      [fingerprint],
    );
    if (byFingerprint.isNotEmpty && byFingerprint.first['id'] != id) return;

    _db.execute(
      '''INSERT INTO speaking_lessons
         (id, source, mode, level_band, title, fingerprint, lesson_json,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           source = excluded.source,
           mode = excluded.mode,
           level_band = excluded.level_band,
           title = excluded.title,
           fingerprint = excluded.fingerprint,
           lesson_json = excluded.lesson_json,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > speaking_lessons.updated_at''',
      [
        id,
        source,
        mode,
        levelBand,
        title,
        fingerprint,
        lessonJson,
        createdAt,
        updatedAt,
      ],
    );
  }

  static String newId() => _speakingUuid.v4();
}
