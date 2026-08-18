import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/services/vocabulary_level_policy.dart';

VocabEntry word(String fr, String en) =>
    VocabEntry(id: fr, fr: fr, en: en, phonetic: '');

void main() {
  test('A1 is limited to the simple phase-one lexical bank', () {
    expect(
      VocabularyLevelPolicy.allowsBundledEntry(
        word('bonjour', 'hello'),
        level: 'a1',
        phase: 1,
      ),
      isTrue,
    );
    expect(
      VocabularyLevelPolicy.allowsBundledEntry(
        word('gouvernement', 'government'),
        level: 'a1',
        phase: 3,
      ),
      isFalse,
    );
    expect(VocabularyLevelPolicy.maxBundledPhase('A1'), 1);
  });

  test('A1 rejects complex lexical cards even inside phase one', () {
    expect(
      VocabularyLevelPolicy.allowsBundledEntry(
        word('je vous prie d’agréer', 'yours sincerely'),
        level: 'a1',
        phase: 1,
      ),
      isFalse,
    );
    expect(
      VocabularyLevelPolicy.allowsGeneratedEntry(
        word('nouveau / nouvelle', 'new'),
        'A1',
      ),
      isFalse,
    );
  });

  test('A2 can use the practical phase-two bank but not phase three', () {
    expect(VocabularyLevelPolicy.maxBundledPhase('A2'), 2);
    expect(
      VocabularyLevelPolicy.allowsBundledEntry(
        word('le travail', 'work'),
        level: 'A2',
        phase: 2,
      ),
      isTrue,
    );
    expect(
      VocabularyLevelPolicy.allowsBundledEntry(
        word('la maîtrise de la langue', 'language proficiency'),
        level: 'A2',
        phase: 3,
      ),
      isFalse,
    );
  });

  test('generated decks are deduplicated and structurally level-gated', () {
    final filtered = VocabularyLevelPolicy.filterGenerated([
      word('bonjour', 'hello'),
      word('bonjour', 'hello again'),
      word('la maîtrise de la langue', 'language proficiency'),
      word('je vous prie d’agréer mes salutations distinguées', 'formal'),
    ], 'A1');
    expect(filtered.map((entry) => entry.fr), ['bonjour']);
  });
}
