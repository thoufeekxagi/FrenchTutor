import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/content_models.dart';
import '../../services/sync_service.dart';
import 'app_migrations.dart';

const _uuid = Uuid();

/// A learner's personal library of AI-generated grammar practice — the
/// Grammar lab's analog of [GeneratedStoryStore] (see `_migrationV16` for the
/// schema rationale). Every "Practice a tense" story is saved here so it has
/// real history, exactly like the Story/Listening library, instead of
/// vanishing the moment the learner leaves the reader screen.
class GeneratedGrammarStory {
  GeneratedGrammarStory({
    required this.id,
    required this.grammarPoint,
    required this.levelBand,
    required this.explanation,
    required this.passage,
    required this.quiz,
    required this.keywords,
    required this.createdAt,
    this.coverUrl,
    this.score,
  });

  final String id;
  final String grammarPoint;
  final String levelBand;

  /// The "teach the rule first" half of the session — generated before the
  /// story and grounding it, so reopening this session from history shows
  /// the same explanation the story was built around.
  final GrammarExplanation explanation;
  final ReadingPassage passage;
  final List<MultipleChoiceQuestion> quiz;
  final List<VocabEntry> keywords;
  final double? score;
  final DateTime createdAt;
  final String? coverUrl;

  String get title => passage.title;
  String get displayTitle => passage.displayTitle;

  /// The tts_audio_cache `content_item_id` tag for one segment's narration —
  /// same convention as `GeneratedStory.segmentContentId`.
  String segmentContentId(int index) => '${id}_seg$index';

  GeneratedGrammarStory copyWith({double? score, String? coverUrl}) =>
      GeneratedGrammarStory(
        id: id,
        grammarPoint: grammarPoint,
        levelBand: levelBand,
        explanation: explanation,
        passage: passage,
        quiz: quiz,
        keywords: keywords,
        createdAt: createdAt,
        score: score ?? this.score,
        coverUrl: coverUrl ?? this.coverUrl,
      );
}

class GeneratedGrammarStoryStore {
  GeneratedGrammarStoryStore(this._db, [this._sync]) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;
  final SyncService? _sync;

  /// All saved grammar sessions, newest first.
  List<GeneratedGrammarStory> list() {
    final rows = _db.select('''SELECT * FROM generated_grammar_stories
         WHERE deleted_at IS NULL
         ORDER BY created_at DESC''');
    return rows.map(_fromRow).toList();
  }

  /// Saves a freshly generated grammar session and pushes it to Supabase
  /// (best-effort, never blocks the caller — same write pattern as every
  /// other store).
  void insert(GeneratedGrammarStory story) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO generated_grammar_stories
         (id, title, grammar_point, level_band, passage_json, quiz_json, keywords_json, explanation_json, score, cover_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        story.id,
        story.title,
        story.grammarPoint,
        story.levelBand,
        jsonEncode(story.passage.toJson()),
        jsonEncode(story.quiz.map((q) => q.toJson()).toList()),
        jsonEncode(story.keywords.map((k) => k.toJson()).toList()),
        jsonEncode(story.explanation.toJson()),
        story.score,
        story.coverUrl,
        story.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
    unawaited(_sync?.syncGeneratedGrammarStory(story));
  }

  /// Records the quiz score once the learner finishes it — mirrors
  /// `GeneratedStoryStore.updateEnrichment`'s "fill in after the fact"
  /// pattern, since the session is saved the moment the story is generated,
  /// before the quiz has been attempted.
  void updateScore(String id, double score) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      'UPDATE generated_grammar_stories SET score = ?, updated_at = ? WHERE id = ?',
      [score, now, id],
    );
    final row = _db.select(
      'SELECT * FROM generated_grammar_stories WHERE id = ?',
      [id],
    );
    if (row.isNotEmpty) {
      unawaited(_sync?.syncGeneratedGrammarStory(_fromRow(row.first)));
    }
  }

  void updateCoverUrl(String id, String coverUrl) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE generated_grammar_stories
         SET cover_url = ?, updated_at = ?
         WHERE id = ?''',
      [coverUrl, now, id],
    );
    final rows = _db.select(
      'SELECT * FROM generated_grammar_stories WHERE id = ?',
      [id],
    );
    if (rows.isNotEmpty) {
      unawaited(_sync?.syncGeneratedGrammarStory(_fromRow(rows.first)));
    }
  }

  /// Upserts a row pulled from Supabase during sign-in hydration.
  /// Last-write-wins on `updated_at`, matching every other hydrate path.
  void upsertFromRemote({
    required String id,
    required String title,
    required String grammarPoint,
    required String levelBand,
    required String passageJson,
    required String quizJson,
    String keywordsJson = '[]',
    String explanationJson = '{}',
    double? score,
    String? coverUrl,
    required String createdAt,
    required String updatedAt,
  }) {
    _db.execute(
      '''INSERT INTO generated_grammar_stories
         (id, title, grammar_point, level_band, passage_json, quiz_json, keywords_json, explanation_json, score, cover_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           grammar_point = excluded.grammar_point,
           level_band = excluded.level_band,
           passage_json = excluded.passage_json,
           quiz_json = excluded.quiz_json,
           keywords_json = excluded.keywords_json,
           explanation_json = excluded.explanation_json,
           score = excluded.score,
           cover_url = excluded.cover_url,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at > generated_grammar_stories.updated_at''',
      [
        id,
        title,
        grammarPoint,
        levelBand,
        passageJson,
        quizJson,
        keywordsJson,
        explanationJson,
        score,
        coverUrl,
        createdAt,
        updatedAt,
      ],
    );
  }

  GeneratedGrammarStory _fromRow(Row row) {
    final passageJson = (jsonDecode(row['passage_json'] as String) as Map)
        .cast<String, dynamic>();
    final quizJson = jsonDecode(row['quiz_json'] as String) as List;
    final keywordsJson =
        jsonDecode(row['keywords_json'] as String? ?? '[]') as List;
    final explanationJson =
        (jsonDecode(row['explanation_json'] as String? ?? '{}') as Map)
            .cast<String, dynamic>();
    return GeneratedGrammarStory(
      id: row['id'] as String,
      grammarPoint: row['grammar_point'] as String,
      levelBand: row['level_band'] as String,
      explanation: explanationJson.isEmpty
          ? GrammarExplanation(
              title: row['grammar_point'] as String,
              summary: '',
              usage: const [],
              tenseContrast: '',
              conjugations: const [],
              examples: const [],
            )
          : GrammarExplanation.fromJson(explanationJson),
      passage: ReadingPassage.fromJson(passageJson),
      quiz: quizJson
          .map((e) => MultipleChoiceQuestion.fromJson((e as Map).cast()))
          .toList(),
      keywords: keywordsJson
          .map((e) => VocabEntry.fromJson((e as Map).cast()))
          .toList(),
      score: (row['score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
      coverUrl: row['cover_url'] as String?,
    );
  }
}

/// Mints a fresh grammar-story id — a full UUID v4, same schema rule as
/// `newGeneratedStoryId()`.
String newGeneratedGrammarStoryId() => _uuid.v4();
