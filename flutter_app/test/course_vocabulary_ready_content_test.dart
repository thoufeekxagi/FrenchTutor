import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/data/database/generated_vocabulary_set_store.dart';
import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/speak/speak_course_vocabulary_screen.dart';

GeneratedVocabularySet preparedSet() {
  final entries = List.generate(
    5,
    (index) => VocabEntry(
      id: 'word-$index',
      en: 'meaning $index',
      fr: 'mot$index',
      phonetic: 'mo-$index',
    ),
  );
  return GeneratedVocabularySet(
    id: 'set-1',
    courseSessionId: 'course-session-6',
    title: 'A prepared morning',
    summary: 'Five connected words.',
    topic: 'Daily routine',
    levelBand: 'A1',
    entries: entries,
    storyExamples: {
      for (final entry in entries)
        entry.id: BilingualExample(
          fr: 'Je pratique ${entry.fr}.',
          en: 'I practise ${entry.en}.',
        ),
    },
    createdAt: DateTime.utc(2026, 9, 5),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  test('persists one complete vocabulary artifact per course session', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = GeneratedVocabularySetStore(db);

    store.insert(preparedSet());
    final restored = store.forCourseSession('course-session-6');

    expect(restored, isNotNull);
    expect(restored!.entries, hasLength(5));
    expect(restored.storyExamples, hasLength(5));
    expect(restored.courseSessionId, 'course-session-6');
  });

  testWidgets('opens prepared vocabulary without a preparation spinner', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: true),
          home: SpeakCourseVocabularyScreen(
            vocabularySet: preparedSet(),
            contentKey: 'adaptive-plan-s006',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Words only'), findsOneWidget);
    expect(find.text('Words + context'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Words + context'));
    await tester.pumpAndSettle();

    expect(find.text('mot0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
