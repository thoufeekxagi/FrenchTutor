import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/writing_course.dart';
import '../../services/sync_service.dart';
import 'app_migrations.dart';

const _writingLessonUuid = Uuid();

/// Durable local library for validated generated Writing V2 lessons.
///
/// The permanent starter bank stays in [WritingCourseCatalog]. Only generated
/// rows live here, so a failed network request can never hide the five bundled
/// lessons in each mode.
class WritingLessonStore {
  WritingLessonStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  List<WritingCourseLesson> list({WritingCourseMode? mode, String? level}) {
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
    final rows = _db.select('''SELECT lesson_json FROM writing_lessons
         WHERE ${where.join(' AND ')}
         ORDER BY created_at ASC''', args);
    final lessons = <WritingCourseLesson>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['lesson_json'] as String);
        if (decoded is Map) {
          lessons.add(
            WritingCourseValidator.validate(
              WritingCourseLesson.fromJson(decoded.cast<String, dynamic>()),
            ),
          );
        }
      } catch (_) {
        // Ignore malformed rows without taking down the Writing home.
      }
    }
    return lessons;
  }

  bool insertGenerated(WritingCourseLesson lesson) {
    final validated = WritingCourseValidator.validate(lesson);
    final fingerprint = writingLessonFingerprint(validated);
    final duplicate = _db.select(
      'SELECT 1 FROM writing_lessons WHERE fingerprint = ? AND deleted_at IS NULL LIMIT 1',
      [fingerprint],
    );
    if (duplicate.isNotEmpty) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO writing_lessons
         (id, mode, level_band, title, fingerprint, lesson_json,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        validated.id,
        validated.mode.name,
        validated.level,
        validated.title,
        fingerprint,
        jsonEncode(validated.toJson()),
        now,
        now,
      ],
    );
    unawaited(_sync?.syncWritingLesson(validated));
    return true;
  }

  void upsertFromRemote({
    required String id,
    required String mode,
    required String levelBand,
    required String title,
    required String fingerprint,
    required String lessonJson,
    required String createdAt,
    required String updatedAt,
  }) {
    final byFingerprint = _db.select(
      'SELECT id FROM writing_lessons WHERE fingerprint = ? AND deleted_at IS NULL LIMIT 1',
      [fingerprint],
    );
    if (byFingerprint.isNotEmpty && byFingerprint.first['id'] != id) return;
    _db.execute(
      '''INSERT INTO writing_lessons
         (id, mode, level_band, title, fingerprint, lesson_json,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           mode = excluded.mode,
           level_band = excluded.level_band,
           title = excluded.title,
           fingerprint = excluded.fingerprint,
           lesson_json = excluded.lesson_json,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > writing_lessons.updated_at''',
      [
        id,
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

  static String newId() => _writingLessonUuid.v4();
}
