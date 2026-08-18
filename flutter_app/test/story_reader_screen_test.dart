import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/lessons/story_reader_screen.dart';
import 'package:french_tutor/widgets/bilingual_word_text.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  testWidgets('renders a generated story sentence by sentence', (
    WidgetTester tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final story = GeneratedStory(
      id: '2c5f81bd-e10e-4ea5-a5f2-62b6f9bb54b5',
      passage: ReadingPassage(
        id: 'reading-passage',
        title: 'Le marché sous la pluie',
        titleEn: 'The rainy market',
        fullText: 'Le marché est vivant. La pluie commence.',
        segments: [
          ReadingSegment(
            fr: 'Le marché est vivant.',
            en: 'The market is lively.',
            grammarNote: 'Uses être for a description.',
            pronunciationTip: '',
          ),
          ReadingSegment(
            fr: 'La pluie commence.',
            en: 'The rain begins.',
            grammarNote: 'Uses the present tense.',
            pronunciationTip: '',
          ),
        ],
      ),
      quiz: const [],
      keywords: const [],
      createdAt: DateTime(2026, 8, 17),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(),
          home: StoryReaderScreen(story: story),
        ),
      ),
    );
    await tester.pump();

    Finder sentence(String source) => find.byWidgetPredicate(
      (widget) => widget is BilingualWordText && widget.source == source,
    );

    expect(sentence('Le marché est vivant.'), findsOneWidget);
    expect(sentence('La pluie commence.'), findsNothing);

    await tester.tap(find.text('Next sentence'));
    await tester.pumpAndSettle();
    expect(sentence('Le marché est vivant.'), findsNothing);
    expect(sentence('La pluie commence.'), findsOneWidget);

    await tester.tap(find.text('Full story'));
    await tester.pumpAndSettle();
    expect(find.text('FULL STORY'), findsOneWidget);
    expect(sentence('Le marché est vivant.'), findsOneWidget);
    expect(sentence('La pluie commence.'), findsOneWidget);

    await tester.tap(find.text('Sentences'));
    await tester.pumpAndSettle();
    expect(sentence('Le marché est vivant.'), findsNothing);
    expect(sentence('La pluie commence.'), findsOneWidget);
  });
}
