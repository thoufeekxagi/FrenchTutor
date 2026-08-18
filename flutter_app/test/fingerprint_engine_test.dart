import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/content_service.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/screens/path/fingerprint_engine.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'fingerprint includes learner-owned generated vocabulary and stories',
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
      );

      expect(graph.isDemo, isFalse);
      expect(
        graph.nodes.map((node) => node.entry.id),
        contains('generated-velo'),
      );
      expect(graph.nodes.single.counts[ModalitySource.recall], greaterThan(0));
    },
  );
}
