import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/content_models.dart';
import '../../services/sync_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../../services/story_variety_service.dart';
import 'app_migrations.dart';

const _uuid = Uuid();

/// A learner's personal library of AI-generated stories — the local cache/
/// write buffer for `generated_stories`, pushed to and pulled from Supabase
/// via [SyncService] (see `_migrationV12` for the schema rationale).
class GeneratedStoryStore {
  GeneratedStoryStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  /// All saved stories, newest first.
  List<GeneratedStory> list({String? practiceMode}) {
    final rows = _db.select(
      '''SELECT id, passage_json, quiz_json, keywords_json, created_at,
                level_band, summary, topic, read_time_minutes, cover_url,
                music_background_url, audio_path, audio_mode, practice_mode
         FROM generated_stories
         WHERE deleted_at IS NULL ${practiceMode == null ? '' : 'AND (practice_mode = ? OR practice_mode IS NULL)'}
         ORDER BY created_at DESC''',
      practiceMode == null ? const [] : [practiceMode],
    );
    final stories = <GeneratedStory>[];
    final fingerprints = <String>{};
    for (final row in rows) {
      try {
        final story = _fromRow(row);
        final opening = story.passage.segments.isEmpty
            ? ''
            : story.passage.segments.first.fr;
        // Older builds could save the same generated response more than once
        // when a screen was reopened during an in-flight request. Keep the
        // newest copy visible while preserving every underlying row for sync
        // and account deletion.
        final fingerprint = StoryVarietyService.storyFingerprint(
          title: story.title,
          opening: opening,
        );
        if (fingerprints.add(fingerprint)) stories.add(story);
      } catch (error, stackTrace) {
        developer.log(
          'Skipping malformed generated story ${row['id']}: $error',
          name: 'GeneratedStoryStore',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return stories;
  }

  /// Saves a freshly generated story and pushes it to Supabase (best-effort,
  /// never blocks the caller — mirrors every other store's write pattern).
  void insert(GeneratedStory story) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_stories
         (id, title, passage_json, quiz_json, keywords_json, level_band,
          summary, topic, read_time_minutes, cover_url, music_background_url,
          audio_path, audio_mode, practice_mode, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        story.id,
        story.title,
        jsonEncode(story.passage.toJson()),
        jsonEncode(story.quiz.map((q) => q.toJson()).toList()),
        jsonEncode(story.keywords.map((k) => k.toJson()).toList()),
        story.levelBand,
        story.summary,
        story.topic,
        story.readTimeMinutes,
        story.coverUrl,
        story.musicBackgroundUrl,
        story.audioPath,
        story.audioMode,
        story.practiceMode,
        story.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
    unawaited(_sync?.syncGeneratedStory(story));
  }

  /// Fills in a story's quiz/keywords after the fact — the story itself is
  /// saved (and shown) the moment its passage is ready; quiz/keywords
  /// generation runs in the background and calls this once it resolves, so
  /// the learner isn't stuck waiting through two Gemini calls before seeing
  /// anything. Pushes the updated row to Supabase too (best-effort).
  void updateEnrichment(GeneratedStory story) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_stories
         SET quiz_json = ?, keywords_json = ?, updated_at = ?
         WHERE id = ?''',
      [
        jsonEncode(story.quiz.map((q) => q.toJson()).toList()),
        jsonEncode(story.keywords.map((k) => k.toJson()).toList()),
        now,
        story.id,
      ],
    );
    unawaited(_sync?.syncGeneratedStory(story));
  }

  /// Stores the generated cover URL after the image request/upload completes.
  /// A cover failure must never invalidate the already-saved text story.
  void updateCoverUrl(String storyId, String coverUrl) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_stories
         SET cover_url = ?, updated_at = ?
         WHERE id = ?''',
      [coverUrl, now, storyId],
    );
    final story = _find(storyId);
    if (story != null) unawaited(_sync?.syncGeneratedStory(story));
  }

  /// Stores the separate portrait artwork used only by the music player.
  void updateMusicBackgroundUrl(String storyId, String musicBackgroundUrl) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_stories
         SET music_background_url = ?, updated_at = ?
         WHERE id = ?''',
      [musicBackgroundUrl, now, storyId],
    );
    final story = _find(storyId);
    if (story != null) unawaited(_sync?.syncGeneratedStory(story));
  }

  /// Upserts a row pulled from Supabase during sign-in hydration.
  /// Last-write-wins on `updated_at`, matching every other hydrate path.
  void upsertFromRemote({
    required String id,
    required String title,
    required String passageJson,
    required String quizJson,
    required String keywordsJson,
    String levelBand = 'A2',
    String summary = '',
    String topic = '',
    int readTimeMinutes = 5,
    String? coverUrl,
    String? musicBackgroundUrl,
    String? audioPath,
    String? audioMode,
    String practiceMode = 'reading',
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO generated_stories
         (id, title, passage_json, quiz_json, keywords_json, level_band,
          summary, topic, read_time_minutes, cover_url, music_background_url,
          audio_path, audio_mode, practice_mode, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           passage_json = excluded.passage_json,
           quiz_json = excluded.quiz_json,
           keywords_json = excluded.keywords_json,
           level_band = excluded.level_band,
           summary = excluded.summary,
           topic = excluded.topic,
           read_time_minutes = excluded.read_time_minutes,
           cover_url = excluded.cover_url,
           music_background_url = excluded.music_background_url,
           audio_path = excluded.audio_path,
           audio_mode = excluded.audio_mode,
           practice_mode = excluded.practice_mode,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > generated_stories.updated_at''',
      [
        id,
        title,
        passageJson,
        quizJson,
        keywordsJson,
        levelBand,
        summary,
        topic,
        readTimeMinutes,
        coverUrl,
        musicBackgroundUrl,
        audioPath,
        audioMode,
        practiceMode,
        createdAt,
        updatedAt,
      ],
    );
  }

  GeneratedStory? _find(String id) {
    final rows = _db.select(
      '''SELECT id, passage_json, quiz_json, keywords_json, created_at,
                level_band, summary, topic, read_time_minutes, cover_url,
                music_background_url, audio_path, audio_mode, practice_mode
         FROM generated_stories WHERE id = ? AND deleted_at IS NULL''',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  GeneratedStory _fromRow(Row row) {
    final passageJson = _decodeMap(row['passage_json']);
    final quizJson = _decodeList(row['quiz_json']);
    final keywordsJson = _decodeList(row['keywords_json']);
    return GeneratedStory(
      id: _string(row['id'], 'generated-story'),
      passage: ReadingPassage.fromJson(passageJson),
      quiz: quizJson
          .whereType<Map>()
          .map(
            (e) => MultipleChoiceQuestion.fromJson(e.cast<String, dynamic>()),
          )
          .toList(),
      keywords: keywordsJson
          .whereType<Map>()
          .map((e) => VocabEntry.fromJson(e.cast<String, dynamic>()))
          .toList(),
      createdAt: _date(row['created_at']),
      levelBand: _string(row['level_band'], 'A2'),
      summary: _string(row['summary']),
      topic: _string(row['topic']),
      readTimeMinutes: _int(row['read_time_minutes']),
      coverUrl: StarterCoverResolver.resolve(
        title: _string(row['title']),
        coverUrl: row['cover_url']?.toString(),
      ),
      musicBackgroundUrl: row['music_background_url']?.toString(),
      audioPath: row['audio_path']?.toString(),
      audioMode: row['audio_mode']?.toString(),
      practiceMode: _string(row['practice_mode'], 'reading'),
    );
  }

  Map<String, dynamic> _decodeMap(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  List<dynamic> _decodeList(Object? value) {
    if (value is List) return value;
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
    }
    return const [];
  }

  String _string(Object? value, [String fallback = '']) =>
      value?.toString() ?? fallback;

  int _int(Object? value, [int fallback = 5]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();
}

/// Mints a fresh story id — a full UUID v4, per this app's schema rule
/// (app_migrations.dart) that every synced row's id round-trips cleanly
/// into a Postgres `uuid` column on Supabase.
String newGeneratedStoryId() => _uuid.v4();
