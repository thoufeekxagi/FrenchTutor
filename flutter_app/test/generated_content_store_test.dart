import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/generated_story_store.dart';
import 'package:french_tutor/data/database/generated_writing_task_store.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('generated story enrichment updates the saved passage translation', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = GeneratedStoryStore(db);
    final story = GeneratedStory(
      id: const Uuid().v4(),
      passage: ReadingPassage(
        id: 'draft-passage',
        title: 'Le matin calme',
        titleEn: 'A Calm Morning',
        fullText: 'Le matin commence.',
        segments: [
          ReadingSegment(
            fr: 'Le matin commence.',
            en: 'Morning starts.',
            grammarNote: '',
            pronunciationTip: '',
          ),
        ],
      ),
      quiz: const [],
      keywords: const [],
      createdAt: DateTime.utc(2026, 8, 28),
    );
    store.insert(story);

    store.updateEnrichment(
      story.copyWith(
        passage: ReadingPassage(
          id: story.passage.id,
          title: story.passage.title,
          titleEn: story.passage.titleEn,
          fullText: story.passage.fullText,
          segments: [
            ReadingSegment(
              fr: 'Le matin commence.',
              en: 'The morning begins.',
              grammarNote: 'Uses the present tense.',
              pronunciationTip: '',
            ),
          ],
        ),
      ),
    );

    final saved = store.list().single;
    expect(saved.passage.segments.single.en, 'The morning begins.');
    expect(
      saved.passage.segments.single.grammarNote,
      'Uses the present tense.',
    );
  });

  test('generated writing tasks survive the local store round trip', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = GeneratedWritingTaskStore(db);
    final task = WritingTask(
      id: const Uuid().v4(),
      type: 'micro',
      title: 'A small plan',
      promptFr: 'Écris cinq mots sur ton week-end.',
      promptEn: 'Write five words about your weekend.',
      minWords: 5,
      targetConnectors: const ['et'],
      rubricHints: const ['Use a simple sentence.'],
      levelBand: 'A1',
      titleEn: 'A small plan',
    );

    store.insert(
      GeneratedWritingTask(task: task, createdAt: DateTime.utc(2026, 8, 17)),
    );
    expect(store.list().single.task.toJson(), task.toJson());

    store.updateCoverUrl(task.id, 'https://example.com/cover.jpg');
    expect(store.list().single.coverUrl, 'https://example.com/cover.jpg');
  });

  test('writing titles follow the learner CEFR level', () {
    final beginner = WritingTask(
      id: const Uuid().v4(),
      type: 'micro',
      title: 'Mon repas favori',
      titleEn: 'My favourite meal',
      promptFr: 'Écris une phrase.',
      promptEn: 'Write one sentence.',
      minWords: 5,
      targetConnectors: const [],
      rubricHints: const [],
      levelBand: 'A1',
    );
    final advanced = WritingTask(
      id: const Uuid().v4(),
      type: 'essay',
      title: 'Le travail à distance',
      titleEn: 'Remote work',
      promptFr: 'Donnez votre opinion.',
      promptEn: 'Give your opinion.',
      minWords: 120,
      targetConnectors: const ['cependant'],
      rubricHints: const [],
      levelBand: 'B2',
    );

    expect(beginner.displayTitle, 'My favourite meal (Mon repas favori)');
    expect(advanced.displayTitle, 'Le travail à distance (Remote work)');
  });

  test('legacy starter title gets a beginner gloss without migration', () {
    final task = WritingTask(
      id: const Uuid().v4(),
      type: 'starter',
      title: 'Un voyage imaginaire',
      promptFr: 'Imagine un voyage.',
      promptEn: 'Imagine a trip.',
      minWords: 5,
      targetConnectors: const [],
      rubricHints: const [],
      levelBand: 'A1',
    );

    expect(task.displayTitle, 'An imaginary trip (Un voyage imaginaire)');
  });
}
