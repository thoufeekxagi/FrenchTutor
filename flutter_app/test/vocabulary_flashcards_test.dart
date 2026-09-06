import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/labs/vocabulary_flashcards_screen.dart';
import 'package:french_tutor/services/vocabulary_story_catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

VocabEntry word(String id) =>
    VocabEntry(id: id, fr: id, en: '$id in English', phonetic: '');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  test('starter vocabulary is five story sets of five linked words', () {
    final sets = VocabularyStoryCatalog.starterSets;

    expect(sets, hasLength(5));
    for (final set in sets) {
      expect(set.entries, hasLength(5));
      expect(set.examplesFor(set.entries), hasLength(5));
      for (final entry in set.entries) {
        final example = set.examplesFor(set.entries)[entry.id];
        expect(example, isNotNull);
        expect(example!.fr, contains(entry.fr));
      }
    }
  });

  testWidgets('teaches one word and reveals its sentence after repeat', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final set = VocabularyStoryCatalog.starterSets.first;
    final entries = set.entries;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: true),
          home: VocabularyFlashcardsScreen(
            title: set.title,
            entries: entries,
            source: 'test',
            topic: set.topic,
            levelBand: set.levelBand,
            storyExamples: set.examplesFor(entries),
            prefetchAudio: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('faim'), findsOneWidget);
    expect(find.text('hungry'), findsNothing);
    expect(find.text('Keep the story in mind.'), findsNothing);
    expect(find.text('œuf'), findsNothing);
    expect(find.text('SENTENCE'), findsNothing);

    await tester.tap(find.text('faim'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('faim'));
    await tester.pumpAndSettle();
    expect(find.text('hungry'), findsOneWidget);
    expect(find.text('Repeat word'), findsOneWidget);
    expect(find.text('J’ai faim ce matin.'), findsNothing);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeat word'));
    await tester.pumpAndSettle();
    expect(find.text('J’ai faim ce matin.'), findsOneWidget);
    expect(find.text('I’m hungry this morning.'), findsOneWidget);
    expect(find.text('Repeat sentence'), findsOneWidget);
    expect(find.text('œuf'), findsNothing);
  });
}
