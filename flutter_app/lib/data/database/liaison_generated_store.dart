import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../liaison_curriculum_catalog.dart';
import 'app_migrations.dart';

/// Local ready queue for GPT-authored Liaison cards. The frozen catalog remains
/// the source of truth for existing progress; generated cards receive their
/// own stable IDs and are only added after the service validates them.
class LiaisonGeneratedLessonStore {
  LiaisonGeneratedLessonStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  List<LiaisonCurriculumLesson> list(String level) {
    final rows = _db.select(
      '''SELECT lesson_json FROM liaison_generated_lessons
         WHERE level = ? AND deleted_at IS NULL
         ORDER BY created_at ASC''',
      [LiaisonCurriculumCatalog.normalizeLevel(level)],
    );
    return rows
        .map(
          (row) => LiaisonCurriculumLesson.fromJson(
            (jsonDecode(row['lesson_json'] as String) as Map)
                .cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  LiaisonCurriculumLesson? byProgressId(String progressId) {
    final id = progressId.startsWith('liaison_curriculum_')
        ? progressId.substring('liaison_curriculum_'.length)
        : '';
    if (id.isEmpty) return null;
    final rows = _db.select(
      '''SELECT lesson_json FROM liaison_generated_lessons
         WHERE id = ? AND deleted_at IS NULL''',
      [id],
    );
    if (rows.isEmpty) return null;
    return LiaisonCurriculumLesson.fromJson(
      (jsonDecode(rows.first['lesson_json'] as String) as Map)
          .cast<String, dynamic>(),
    );
  }

  void insertAll(Iterable<LiaisonCurriculumLesson> lessons) {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final lesson in lessons) {
      _db.execute(
        '''INSERT OR IGNORE INTO liaison_generated_lessons
           (id, level, lesson_json, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)''',
        [lesson.id, lesson.level, jsonEncode(lesson.toJson()), now, now],
      );
    }
  }
}
