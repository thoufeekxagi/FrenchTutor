import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../models/content_models.dart';
import '../../services/sync_service.dart';
import '../../services/starter_cover_resolver.dart';
import 'app_migrations.dart';

/// A generated writing prompt saved as learner-owned content. The prompt is
/// immutable lesson content; submissions remain in the existing submission
/// stream, while this store makes the prompt itself reopenable after leaving
/// the lab or reinstalling the app.
class GeneratedWritingTask {
  const GeneratedWritingTask({
    required this.task,
    required this.createdAt,
    this.coverUrl,
  });

  final WritingTask task;
  final DateTime createdAt;
  final String? coverUrl;

  String get id => task.id;

  GeneratedWritingTask copyWith({String? coverUrl}) => GeneratedWritingTask(
    task: task,
    createdAt: createdAt,
    coverUrl: coverUrl ?? this.coverUrl,
  );
}

class GeneratedWritingTaskStore {
  GeneratedWritingTaskStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  List<GeneratedWritingTask> list() {
    final rows = _db.select('''
      SELECT id, task_json, created_at, cover_url
      FROM generated_writing_tasks
      WHERE deleted_at IS NULL
      ORDER BY created_at DESC
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  void insert(GeneratedWritingTask generated) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_writing_tasks
         (id, task_json, level_band, cover_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [
        generated.id,
        jsonEncode(generated.task.toJson()),
        generated.task.levelBand,
        generated.coverUrl,
        generated.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
    unawaited(_sync?.syncGeneratedWritingTask(generated));
  }

  void updateCoverUrl(String id, String coverUrl) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_writing_tasks
         SET cover_url = ?, updated_at = ?
         WHERE id = ?''',
      [coverUrl, now, id],
    );
    final rows = _db.select(
      '''SELECT id, task_json, created_at, cover_url
         FROM generated_writing_tasks WHERE id = ? AND deleted_at IS NULL''',
      [id],
    );
    if (rows.isNotEmpty) {
      unawaited(_sync?.syncGeneratedWritingTask(_fromRow(rows.first)));
    }
  }

  void upsertFromRemote({
    required String id,
    required String taskJson,
    String? levelBand,
    String? coverUrl,
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO generated_writing_tasks
         (id, task_json, level_band, cover_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           task_json = excluded.task_json,
           level_band = excluded.level_band,
           cover_url = excluded.cover_url,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > generated_writing_tasks.updated_at''',
      [id, taskJson, levelBand ?? 'A2', coverUrl, createdAt, updatedAt],
    );
  }

  GeneratedWritingTask _fromRow(Row row) {
    final raw = row['task_json'];
    final decoded = raw is String ? jsonDecode(raw) : raw;
    final task = WritingTask.fromJson((decoded as Map).cast<String, dynamic>());
    return GeneratedWritingTask(
      task: task,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      coverUrl: StarterCoverResolver.resolve(
        title: task.title,
        coverUrl: row['cover_url']?.toString(),
      ),
    );
  }
}
