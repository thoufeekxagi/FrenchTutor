import 'package:sqlite3/common.dart';

import 'app_migrations.dart';

/// Index for persisted Gemini TTS audio files — see `_migrationV9` in
/// `app_migrations.dart`. Stores only the file name (the audio bytes live on
/// disk under the app's persistent support directory); this table exists so
/// a cached line can be looked up and reused across app relaunches, and
/// optionally traced back to the vocab/grammar/listening/writing item it
/// belongs to.
class TtsAudioCacheStore {
  TtsAudioCacheStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  /// The cached file name for [cacheKey], or null on a cache miss.
  String? fileName(String cacheKey) {
    final rows = _db.select(
      'SELECT file_name FROM tts_audio_cache WHERE cache_key = ?',
      [cacheKey],
    );
    if (rows.isEmpty) return null;
    return rows.first['file_name'] as String;
  }

  /// Records a freshly synthesized line. [contentItemId] is optional metadata
  /// (the vocab word / grammar lesson / listening line this audio belongs
  /// to) — omitted, the row is still fully keyed and reusable by
  /// voice+slow+text alone.
  void record({
    required String cacheKey,
    required String voiceName,
    required bool slow,
    required String text,
    required String fileName,
    String? contentItemId,
  }) {
    _db.execute(
      '''INSERT OR REPLACE INTO tts_audio_cache
         (cache_key, content_item_id, voice_name, slow, text, file_name, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        cacheKey,
        contentItemId,
        voiceName,
        slow ? 1 : 0,
        text,
        fileName,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }
}
