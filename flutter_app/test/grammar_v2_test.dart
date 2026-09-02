import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/data/grammar_curriculum_catalog.dart';
import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/design/tokens.dart';
import 'package:french_tutor/models/grammar_course_v2.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/grammar/grammar_v2_home_screen.dart';
import 'package:french_tutor/screens/grammar/grammar_v2_lesson_screen.dart';
import 'package:french_tutor/services/app_appearance_settings.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  tearDown(() => AppAppearanceSettings.shared.adoptDarkMode(true));

  test('tense filter exposes the requested stable options', () {
    expect(GrammarCurriculumCatalog.all.first.sentenceTiles, [
      'Une',
      'table',
      'est',
      'libre',
      '.',
    ]);
    expect(GrammarV2Tenses.values, [
      GrammarV2Tenses.all,
      GrammarV2Tenses.present,
      GrammarV2Tenses.past,
      GrammarV2Tenses.future,
      GrammarV2Tenses.mixed,
    ]);
    expect(
      GrammarV2Tenses.matches(
        GrammarCurriculumCatalog.all.first,
        GrammarV2Tenses.all,
      ),
      isTrue,
    );
    for (final filter in GrammarV2Tenses.values) {
      final lessons = GrammarCurriculumCatalog.all
          .where((lesson) => GrammarV2Tenses.matches(lesson, filter))
          .take(5)
          .toList();
      expect(lessons, isNotEmpty, reason: filter);
    }
    for (final filter in [GrammarV2Tenses.past, GrammarV2Tenses.future]) {
      final starterReserve = grammarV2FallbackLessons
          .where((lesson) => GrammarV2Tenses.matches(lesson, filter))
          .toList();
      expect(starterReserve, hasLength(5), reason: filter);
    }
  });

  testWidgets('Grammar home uses five square cards and mode picker', (
    tester,
  ) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: false),
          home: GrammarV2HomeScreen(
            generatedHistory: const [],
            isGenerating: false,
            generationError: null,
            onGenerateAdvanced: (_) async {},
            onOpenGenerated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build your grammar'), findsOneWidget);
    expect(find.text('Guided'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Roleplay'), findsOneWidget);
    await tester.tap(find.text('Mixed'));
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pump();
    expect(find.byType(GridView, skipOffstage: false), findsOneWidget);
    final grid = tester.widget<GridView>(
      find.byType(GridView, skipOffstage: false),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(delegate.childAspectRatio, 1);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Grammar lesson has no typing and supports all three modes', (
    tester,
  ) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final lesson = GrammarCurriculumCatalog.forLevel('A1').first;
    for (final mode in GrammarV2Mode.values) {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.themeData(darkMode: false),
            home: GrammarV2LessonScreen(lesson: lesson, mode: mode),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: mode.label);
      expect(find.textContaining(mode.label.toUpperCase()), findsOneWidget);
      expect(
        find.byIcon(Icons.translate_rounded, skipOffstage: false),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('each Grammar mode checks its frozen answer', (tester) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final lesson = GrammarCurriculumCatalog.forLevel('A1').first;

    Future<void> pumpMode(GrammarV2Mode mode) async {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.themeData(darkMode: false),
            home: GrammarV2LessonScreen(lesson: lesson, mode: mode),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpMode(GrammarV2Mode.guided);
    final guidedChoice = find.text(lesson.pickAnswer).last;
    await tester.ensureVisible(guidedChoice);
    await tester.tap(guidedChoice);
    await tester.pump();
    await tester.ensureVisible(find.text('Check form'));
    await tester.tap(find.text('Check form'));
    await tester.pump();
    expect(
      find.textContaining('Correct.', skipOffstage: false),
      findsOneWidget,
    );

    await pumpMode(GrammarV2Mode.complete);
    final shuffledWords = [...lesson.sentenceTiles]
      ..shuffle(math.Random(lesson.id.hashCode));
    final usedWordIndexes = <int>{};
    for (final word in lesson.sentenceTiles) {
      var index = -1;
      for (
        var candidateIndex = 0;
        candidateIndex < shuffledWords.length;
        candidateIndex++
      ) {
        if (!usedWordIndexes.contains(candidateIndex) &&
            shuffledWords[candidateIndex] == word) {
          index = candidateIndex;
          break;
        }
      }
      expect(index, greaterThanOrEqualTo(0));
      usedWordIndexes.add(index);
      final wordFinder = find.byKey(
        ValueKey('grammar-v2-word-bank-${lesson.id}-$index'),
      );
      await tester.ensureVisible(wordFinder);
      await tester.tap(wordFinder, warnIfMissed: false);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Check sentence'));
    await tester.tap(find.text('Check sentence'));
    await tester.pump();
    expect(
      find.textContaining('Correct.', skipOffstage: false),
      findsOneWidget,
    );

    await pumpMode(GrammarV2Mode.roleplay);
    final roleplayChoice = find.byKey(
      ValueKey('grammar-v2-roleplay-choice-${lesson.id}-${lesson.pickAnswer}'),
    );
    await tester.ensureVisible(roleplayChoice);
    final roleplayTapTarget = find.descendant(
      of: roleplayChoice,
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(roleplayTapTarget).onTap!.call();
    await tester.pump();
    await tester.ensureVisible(find.text('Check reply'));
    await tester.pump();
    await tester.tap(find.text('Check reply'));
    await tester.pump();
    expect(
      find.textContaining('Correct.', skipOffstage: false),
      findsOneWidget,
    );
  });
}
