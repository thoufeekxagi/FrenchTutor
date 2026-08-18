import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/utils/vocabulary_set_copy.dart';

void main() {
  GeneratedVocabularySet set({
    required String title,
    required String summary,
    List<VocabEntry> entries = const [],
  }) => GeneratedVocabularySet(
    id: 'set',
    title: title,
    summary: summary,
    topic: 'Recommended vocabulary',
    levelBand: 'A1',
    entries: entries,
    createdAt: DateTime.utc(2026, 8, 18),
  );

  test('keeps a specific saved title and exposes its context', () {
    final vocabulary = set(
      title: 'A morning at the market',
      summary: 'Practice choosing fruit and asking the price.',
    );

    expect(VocabularySetCopy.title(vocabulary), 'A morning at the market');
    expect(
      VocabularySetCopy.summary(
        vocabulary,
        displayedTitle: 'A morning at the market',
      ),
      'Practice choosing fruit and asking the price',
    );
  });

  test('upgrades older generic cards using their stored focus note', () {
    final vocabulary = set(
      title: "Today's Words",
      summary: 'A short market story helps you reuse these words.',
    );

    expect(
      VocabularySetCopy.title(vocabulary),
      'A short market story helps you reuse these words',
    );
  });

  test('falls back to the actual words when the old record has no context', () {
    final vocabulary = set(
      title: "Today's Words",
      summary: 'A saved vocabulary practice set built from the words selected.',
      entries: [
        VocabEntry(id: 'market', en: 'market', fr: 'marché', phonetic: ''),
        VocabEntry(id: 'price', en: 'price', fr: 'prix', phonetic: ''),
      ],
    );

    expect(VocabularySetCopy.title(vocabulary), 'Market, price');
  });
}
