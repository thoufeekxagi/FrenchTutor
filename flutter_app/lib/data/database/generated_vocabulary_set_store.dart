import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../models/content_models.dart';
import '../../services/sync_service.dart';
import '../../services/starter_cover_resolver.dart';
import 'app_migrations.dart';

/// Local cache/write buffer for learner-owned vocabulary libraries.
class GeneratedVocabularySetStore {
  GeneratedVocabularySetStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  List<GeneratedVocabularySet> list() {
    final rows = _db.select('''
      SELECT id, title, summary, topic, level_band, entries_json,
             cover_url, created_at
      FROM generated_vocabulary_sets
      WHERE deleted_at IS NULL
      ORDER BY created_at DESC
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  void insert(GeneratedVocabularySet set) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_vocabulary_sets
         (id, title, summary, topic, level_band, entries_json, cover_url,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        set.id,
        set.title,
        set.summary,
        set.topic,
        set.levelBand,
        jsonEncode(set.entries.map((entry) => entry.toJson()).toList()),
        set.coverUrl,
        set.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
    unawaited(_sync?.syncGeneratedVocabularySet(set));
  }

  void updateCoverUrl(String id, String coverUrl) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_vocabulary_sets
         SET cover_url = ?, updated_at = ?
         WHERE id = ?''',
      [coverUrl, now, id],
    );
    final rows = _db.select(
      '''SELECT id, title, summary, topic, level_band, entries_json,
                cover_url, created_at
         FROM generated_vocabulary_sets
         WHERE id = ? AND deleted_at IS NULL''',
      [id],
    );
    if (rows.isNotEmpty) {
      unawaited(_sync?.syncGeneratedVocabularySet(_fromRow(rows.first)));
    }
  }

  void upsertFromRemote({
    required String id,
    required String title,
    required String summary,
    required String topic,
    required String levelBand,
    required String entriesJson,
    String? coverUrl,
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO generated_vocabulary_sets
         (id, title, summary, topic, level_band, entries_json, cover_url,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           summary = excluded.summary,
           topic = excluded.topic,
           level_band = excluded.level_band,
           entries_json = excluded.entries_json,
           cover_url = excluded.cover_url,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > generated_vocabulary_sets.updated_at''',
      [
        id,
        title,
        summary,
        topic,
        levelBand,
        entriesJson,
        coverUrl,
        createdAt,
        updatedAt,
      ],
    );
  }

  GeneratedVocabularySet _fromRow(Row row) {
    final raw = row['entries_json'];
    final decoded = raw is String && raw.trim().isNotEmpty
        ? jsonDecode(raw)
        : const <dynamic>[];
    return GeneratedVocabularySet(
      id: row['id'] as String,
      title: row['title'] as String,
      summary: row['summary'] as String? ?? '',
      topic: row['topic'] as String? ?? '',
      levelBand: row['level_band'] as String? ?? 'A1',
      entries: (decoded as List)
          .whereType<Map>()
          .map((entry) => VocabEntry.fromJson(entry.cast<String, dynamic>()))
          .toList(),
      coverUrl: StarterCoverResolver.resolve(
        title: row['title'] as String,
        coverUrl: row['cover_url'] as String?,
      ),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
