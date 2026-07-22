import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/content_models.dart';
import 'app_migrations.dart';

const _uuid = Uuid();

/// A small rotating pool of pre-generated roleplay scenes per mission (see
/// `_migrationV10`). A mission's prompt (title/scenario/level/promptContext +
/// speaking topic) is identical for every learner who gets it, so a scene
/// generated for one learner is fully reusable by the next — this store lets
/// callers build up to [poolSize] variants per mission and then cycle
/// through them by least-recently-used, instead of calling Gemini again on
/// every mission visit by every learner.
class GeneratedSceneCacheStore {
  GeneratedSceneCacheStore(this._db, {this.poolSize = 5}) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  /// Target variants per mission — 5 per mission across the current 5-mission
  /// catalog lands the whole cache around 25 scenes, matching what was agreed
  /// on as "roughly two days ahead" of pre-generated content. Grows
  /// automatically as more missions are authored, without a code change.
  final int poolSize;

  int variantCount(String missionId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM generated_scene_cache WHERE mission_id = ?',
      [missionId],
    );
    return rows.first['n'] as int;
  }

  /// True while this mission's variant pool is still below [poolSize] — the
  /// caller should generate a fresh scene and [store] it rather than reuse.
  bool needsNewVariant(String missionId) => variantCount(missionId) < poolSize;

  /// True once a mission's pool has drained down near empty — the trigger for
  /// a background top-up rather than an immediate, blocking one. A pool never
  /// actually empties in normal use (variants rotate, they aren't consumed),
  /// so this mainly fires right after a mission is added to the catalog or
  /// after a fresh install before warm-up has had a chance to run.
  bool isRunningLow(String missionId, {int lowWaterMark = 2}) =>
      variantCount(missionId) <= lowWaterMark;

  /// The least-recently-used cached variant for [missionId], or null if none
  /// exist yet. Marks it used (bumps `times_used`/`last_used_at`) so the pool
  /// rotates rather than always handing back the same one.
  ReadingPassage? takeVariant(String missionId) {
    final rows = _db.select(
      '''SELECT id, scene_json FROM generated_scene_cache
         WHERE mission_id = ?
         ORDER BY last_used_at IS NOT NULL, last_used_at ASC, created_at ASC
         LIMIT 1''',
      [missionId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    _db.execute(
      '''UPDATE generated_scene_cache
         SET times_used = times_used + 1, last_used_at = ?
         WHERE id = ?''',
      [DateTime.now().toUtc().toIso8601String(), row['id'] as String],
    );
    final json = (jsonDecode(row['scene_json'] as String) as Map)
        .cast<String, dynamic>();
    return ReadingPassage.fromJson(json);
  }

  /// Adds a freshly generated scene to the pool for [missionId].
  void store(String missionId, ReadingPassage scene) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_scene_cache
         (id, mission_id, scene_json, times_used, created_at, last_used_at)
         VALUES (?, ?, ?, 0, ?, ?)''',
      [_uuid.v4(), missionId, jsonEncode(scene.toJson()), now, now],
    );
  }
}
