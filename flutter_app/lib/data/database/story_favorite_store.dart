import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/sync_service.dart';
import 'app_migrations.dart';

/// Local cache for the learner's starred stories.
///
/// The user id is part of the primary key so a shared device cannot make one
/// learner's favorites appear in another learner's library.  Anonymous use is
/// kept local under a stable fallback key; signed-in changes are also pushed
/// through [SyncService] and restored during sign-in hydration.
class StoryFavoriteStore {
  StoryFavoriteStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  String get _userId =>
      Supabase.instance.client.auth.currentUser?.id ?? 'local-device';

  bool isFavorite(String storyId) {
    return _db.select(
      'SELECT 1 FROM story_favorites WHERE user_id = ? AND story_id = ?',
      [_userId, storyId],
    ).isNotEmpty;
  }

  List<String> favoriteStoryIds() {
    return _db
        .select(
          'SELECT story_id FROM story_favorites WHERE user_id = ? '
          'ORDER BY updated_at DESC',
          [_userId],
        )
        .map((row) => row['story_id'].toString())
        .toList();
  }

  void setFavorite(String storyId, bool favorite) {
    final now = DateTime.now().toUtc().toIso8601String();
    if (favorite) {
      _db.execute(
        '''INSERT INTO story_favorites (user_id, story_id, created_at, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(user_id, story_id) DO UPDATE SET updated_at = excluded.updated_at''',
        [_userId, storyId, now, now],
      );
    } else {
      _db.execute(
        'DELETE FROM story_favorites WHERE user_id = ? AND story_id = ?',
        [_userId, storyId],
      );
    }
    unawaited(_sync?.syncStoryFavorite(storyId: storyId, favorite: favorite));
  }

  void upsertFromRemote({
    required String userId,
    required String storyId,
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO story_favorites (user_id, story_id, created_at, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id, story_id) DO UPDATE SET
           created_at = excluded.created_at,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > story_favorites.updated_at''',
      [userId, storyId, createdAt, updatedAt],
    );
  }
}
