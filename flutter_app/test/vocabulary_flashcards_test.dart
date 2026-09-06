import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/labs/vocabulary_flashcards_screen.dart';
import 'package:french_tutor/services/tutor_helper_settings.dart';
import 'package:french_tutor/services/vocabulary_story_catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

VocabEntry word(String id) =>
    VocabEntry(id: id, fr: id, en: '$id in English', phonetic: '');

void main() {
  setUpAll(() async {
    // Vocabulary's tutor-helper (live pronunciation check) defaults to on;
    // keep it off here so this test exercises the plain mic-capture fallback
    // path deterministically, without depending on a real Gemini Live call
    // or the AI voice consent dialog.
    SharedPreferences.setMockInitialValues({
      'tutor_helper_enabled_vocabulary': false,
    });
    // Loading is otherwise fire-and-forget from the provider; wait for it
    // here so the screen never races it and reads the (wrong) in-memory
    // default before the persisted "off" value has loaded.
    await TutorHelperSettings.shared.load();
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
    // The word only becomes complete once the learner is actually heard
    // saying it (verified through Gemini's transcript), so this screen must
    // show the record prompt here, not an auto-completing button — using
    // the same footer layout (translate / record-stop-next / replay)
    // Speaking Guided uses.
    expect(find.text('Record'), findsOneWidget);
    // The feedback card sits below the word card and can be scrolled past
    // the fixed test viewport; scroll it into view before asserting on it.
    await tester.dragUntilVisible(
      find.text('Speak now'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Speak now'), findsOneWidget);
    expect(find.text('Repeat word'), findsNothing);
    expect(find.text('J’ai faim ce matin.'), findsNothing);
  });
}
