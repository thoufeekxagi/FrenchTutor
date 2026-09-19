import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/content_service.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/screens/path/fingerprint_engine.dart';
import 'package:french_tutor/services/universal_learning_data_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'fingerprint includes generated vocabulary only after recent practice',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final store = LearningStore(db);
      final word = VocabEntry(
        id: 'generated-velo',
        en: 'bike',
        fr: 'vélo',
        phonetic: 'vay-lo',
      );
      final story = GeneratedStory(
        id: 'generated-story',
        passage: ReadingPassage(
          id: 'passage',
          title: 'Le vélo rouge',
          segments: const [],
          fullText: 'Je prends mon vélo rouge.',
        ),
        quiz: const [],
        keywords: [word],
        createdAt: DateTime.utc(2026, 8, 17),
      );

      final graph = buildFingerprintGraph(
        store,
        ContentService.shared,
        vocabularySets: [
          GeneratedVocabularySet(
            id: 'generated-set',
            title: 'Transport',
            summary: '',
            topic: 'travel',
            levelBand: 'A1',
            entries: [word],
            createdAt: DateTime.utc(2026, 8, 17),
          ),
        ],
        stories: [story],
        recentSnapshot: UniversalLearningSnapshot(
          fingerprint: 'test',
          evidence: [
            UniversalLearningEvidence(
              id: 'completed-reading',
              source: 'course',
              mode: 'reading',
              topic: 'Transport',
              summary: 'Completed reading practice',
              occurredAt: DateTime.utc(2026, 8, 17),
              details: const ['Je prends mon vélo rouge.'],
            ),
          ],
          sourceSessionIds: const ['completed-reading'],
          recentTopics: const ['Transport'],
          transcriptExcerpts: const [],
          writingSignals: const [],
          vocabularySignals: const [],
          examSignals: const [],
          performanceSignals: const [],
          repeatedMistakes: const [],
          targetPhrases: const [],
          recentSkills: const [],
          courseSessionCount: 1,
          practiceSessionCount: 0,
        ),
      );

      expect(graph.isDemo, isFalse);
      expect(
        graph.nodes.map((node) => node.entry.id),
        contains('generated-velo'),
      );
      expect(graph.nodes.single.counts[ModalitySource.recall], greaterThan(0));
    },
  );

  test('fingerprint never renders a three-word node', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = LearningStore(db);
    final phrase = VocabEntry(
      id: 'long-target',
      en: 'a very red bike',
      fr: 'très grand vélo',
      phonetic: '',
    );
    final graph = buildFingerprintGraph(
      store,
      ContentService.shared,
      vocabularySets: [
        GeneratedVocabularySet(
          id: 'set',
          title: 'Transport',
          summary: '',
          topic: 'transport',
          levelBand: 'A1',
          entries: [phrase],
          createdAt: DateTime.utc(2026, 8, 17),
        ),
      ],
      recentSnapshot: UniversalLearningSnapshot(
        fingerprint: 'test',
        evidence: [
          UniversalLearningEvidence(
            id: 'done',
            source: 'course',
            mode: 'vocabulary',
            topic: 'Transport',
            summary: '',
            occurredAt: DateTime.utc(2026, 8, 17),
            details: const ['très grand vélo'],
          ),
        ],
        sourceSessionIds: const ['done'],
        recentTopics: const [],
        transcriptExcerpts: const [],
        writingSignals: const [],
        vocabularySignals: const [],
        examSignals: const [],
        performanceSignals: const [],
        repeatedMistakes: const [],
        targetPhrases: const [],
        recentSkills: const [],
        courseSessionCount: 1,
        practiceSessionCount: 0,
      ),
    );

    expect(graph.isDemo, isFalse);
    expect(
      graph.nodes.every(
        (node) => node.entry.fr.trim().split(RegExp(r'\s+')).length <= 2,
      ),
      isTrue,
    );
  });
}
