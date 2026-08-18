import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/content_models.dart';
import '../../services/sync_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../../services/story_variety_service.dart';
import 'app_migrations.dart';

const _uuid = Uuid();

/// A learner's personal library of AI-generated roleplay scenes — the local
/// cache/write buffer for `generated_roleplays`, pushed to and pulled from
/// Supabase via [SyncService] (see `_migrationV13` for the schema rationale).
/// Mirrors [GeneratedStoryStore] exactly, minus the quiz/keywords columns a
/// roleplay scene has no use for.
class GeneratedRoleplayStore {
  GeneratedRoleplayStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  /// All saved roleplays, newest first.
  List<GeneratedRoleplay> list() {
    final rows = _db.select(
      '''SELECT id, passage_json, level_band, created_at, cover_url
         FROM generated_roleplays
         WHERE deleted_at IS NULL
         ORDER BY created_at DESC''',
    );
    final roleplays = <GeneratedRoleplay>[];
    final fingerprints = <String>{};
    for (final row in rows) {
      final roleplay = _fromRow(row);
      final fingerprint = StoryVarietyService.storyFingerprint(
        title: roleplay.title,
        opening: roleplay.passage.segments.firstOrNull?.fr ?? '',
      );
      if (fingerprints.add(fingerprint)) roleplays.add(roleplay);
    }
    return roleplays;
  }

  /// Saves a freshly generated roleplay and pushes it to Supabase
  /// (best-effort, never blocks the caller — mirrors every other store's
  /// write pattern).
  void insert(GeneratedRoleplay roleplay) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_roleplays
         (id, title, passage_json, level_band, cover_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        roleplay.id,
        roleplay.title,
        jsonEncode(roleplay.passage.toJson()),
        roleplay.levelBand,
        roleplay.coverUrl,
        roleplay.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
    unawaited(_sync?.syncGeneratedRoleplay(roleplay));
  }

  /// Upserts a row pulled from Supabase during sign-in hydration.
  /// Last-write-wins on `updated_at`, matching every other hydrate path.
  void upsertFromRemote({
    required String id,
    required String title,
    required String passageJson,
    String levelBand = 'A1',
    String? coverUrl,
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO generated_roleplays
         (id, title, passage_json, level_band, cover_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           passage_json = excluded.passage_json,
           level_band = excluded.level_band,
           cover_url = excluded.cover_url,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > generated_roleplays.updated_at''',
      [id, title, passageJson, levelBand, coverUrl, createdAt, updatedAt],
    );
  }

  /// Stores the generated cover URL after image generation/upload completes.
  /// A cover failure never invalidates the already-saved roleplay scene.
  void updateCoverUrl(String roleplayId, String coverUrl) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_roleplays
         SET cover_url = ?, updated_at = ?
         WHERE id = ?''',
      [coverUrl, now, roleplayId],
    );
    final roleplay = _find(roleplayId);
    if (roleplay != null) unawaited(_sync?.syncGeneratedRoleplay(roleplay));
  }

  GeneratedRoleplay? _find(String id) {
    final rows = _db.select(
      '''SELECT id, passage_json, level_band, created_at, cover_url
         FROM generated_roleplays
         WHERE id = ? AND deleted_at IS NULL''',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  GeneratedRoleplay _fromRow(Row row) {
    final passageJson = (jsonDecode(row['passage_json'] as String) as Map)
        .cast<String, dynamic>();
    final passage = ReadingPassage.fromJson(passageJson);
    return GeneratedRoleplay(
      id: row['id'] as String,
      passage: passage,
      createdAt: DateTime.parse(row['created_at'] as String),
      levelBand: row['level_band'] as String? ?? 'A1',
      coverUrl: StarterCoverResolver.resolve(
        title: passage.title,
        coverUrl: row['cover_url'] as String?,
      ),
    );
  }
}

/// Mints a fresh roleplay id — a full UUID v4, per this app's schema rule
/// that every synced row's id round-trips cleanly into a Postgres `uuid`
/// column on Supabase.
String newGeneratedRoleplayId() => _uuid.v4();
