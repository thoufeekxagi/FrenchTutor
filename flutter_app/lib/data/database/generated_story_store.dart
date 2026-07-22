import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/content_models.dart';
import '../../services/sync_service.dart';
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
  List<GeneratedStory> list() {
    final rows = _db.select(
      '''SELECT id, passage_json, quiz_json, keywords_json, created_at
         FROM generated_stories
         WHERE deleted_at IS NULL
         ORDER BY created_at DESC''',
    );
    return rows.map(_fromRow).toList();
  }

  /// Saves a freshly generated story and pushes it to Supabase (best-effort,
  /// never blocks the caller — mirrors every other store's write pattern).
  void insert(GeneratedStory story) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_stories
         (id, title, passage_json, quiz_json, keywords_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        story.id,
        story.title,
        jsonEncode(story.passage.toJson()),
        jsonEncode(story.quiz.map((q) => q.toJson()).toList()),
        jsonEncode(story.keywords.map((k) => k.toJson()).toList()),
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

  /// Upserts a row pulled from Supabase during sign-in hydration.
  /// Last-write-wins on `updated_at`, matching every other hydrate path.
  void upsertFromRemote({
    required String id,
    required String title,
    required String passageJson,
    required String quizJson,
    required String keywordsJson,
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO generated_stories
         (id, title, passage_json, quiz_json, keywords_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           passage_json = excluded.passage_json,
           quiz_json = excluded.quiz_json,
           keywords_json = excluded.keywords_json,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > generated_stories.updated_at''',
      [id, title, passageJson, quizJson, keywordsJson, createdAt, updatedAt],
    );
  }

  GeneratedStory _fromRow(Row row) {
    final passageJson = (jsonDecode(row['passage_json'] as String) as Map)
        .cast<String, dynamic>();
    final quizJson = jsonDecode(row['quiz_json'] as String) as List;
    final keywordsJson = jsonDecode(row['keywords_json'] as String) as List;
    return GeneratedStory(
      id: row['id'] as String,
      passage: ReadingPassage.fromJson(passageJson),
      quiz: quizJson
          .map((e) => MultipleChoiceQuestion.fromJson((e as Map).cast()))
          .toList(),
      keywords: keywordsJson
          .map((e) => VocabEntry.fromJson((e as Map).cast()))
          .toList(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

/// Mints a fresh story id — a full UUID v4, per this app's schema rule
/// (app_migrations.dart) that every synced row's id round-trips cleanly
/// into a Postgres `uuid` column on Supabase.
String newGeneratedStoryId() => _uuid.v4();
