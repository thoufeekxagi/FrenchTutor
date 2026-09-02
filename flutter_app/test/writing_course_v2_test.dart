import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/data/database/writing_lesson_store.dart';
import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/models/writing_course.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/labs/writing_course_home_screen.dart';
import 'package:french_tutor/screens/lessons/writing_course_lesson_screen.dart';
import 'package:french_tutor/services/app_appearance_settings.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  tearDown(() {
    AppAppearanceSettings.shared.adoptDarkMode(true);
  });

  test('starter catalog has exactly five validated lessons in each mode', () {
    for (final mode in WritingCourseMode.values) {
      final lessons = WritingCourseCatalog.forMode(mode);
      expect(lessons, hasLength(5), reason: mode.name);
      for (final lesson in lessons) {
        expect(WritingCourseValidator.validate(lesson), same(lesson));
        for (var stepIndex = 0; stepIndex < lesson.steps.length; stepIndex++) {
          final step = lesson.steps[stepIndex];
          for (final meaning in step.tokenMeanings) {
            expect(
              meaning,
              isNot('French phrase'),
              reason:
                  '${lesson.id} step $stepIndex token meanings ${step.tokens}',
            );
          }
          for (final meaning in step.choiceMeanings) {
            expect(
              meaning,
              isNot('French phrase'),
              reason:
                  '${lesson.id} step $stepIndex choice meanings ${step.choices}',
            );
          }
          for (final meaning in step.suggestionMeanings) {
            expect(
              meaning,
              isNot('French phrase'),
              reason:
                  '${lesson.id} step $stepIndex suggestion meanings ${step.suggestions}',
            );
          }
        }
      }
    }
  });

  test(
    'every guided word bank matches its target, including the final help line',
    () {
      final guided = WritingCourseCatalog.forMode(WritingCourseMode.guided);
      for (final lesson in guided) {
        for (var stepIndex = 0; stepIndex < lesson.steps.length; stepIndex++) {
          final step = lesson.steps[stepIndex];
          expect(
            step.tokens.join(' '),
            step.target,
            reason:
                '${lesson.title} step ${stepIndex + 1} drifted from its target',
          );
        }
      }

      final askForHelp = guided.firstWhere(
        (lesson) => lesson.title == 'Ask for help',
      );
      expect(askForHelp.steps.last.target, 'Merci beaucoup pour votre aide.');
      expect(askForHelp.steps.last.tokens, [
        'Merci',
        'beaucoup',
        'pour',
        'votre',
        'aide.',
      ]);
    },
  );

  test('generated writing store rejects duplicate fingerprints', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = WritingLessonStore(db);
    final lesson = WritingCourseCatalog.forMode(WritingCourseMode.guided).first;

    expect(store.insertGenerated(lesson), isTrue);
    expect(store.insertGenerated(lesson), isFalse);
    expect(store.list(mode: WritingCourseMode.guided), hasLength(1));
  });

  testWidgets('writing home exposes five cards per mode in light and dark', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    Future<void> pumpWithAppearance(bool dark) async {
      AppAppearanceSettings.shared.adoptDarkMode(dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.themeData(darkMode: dark),
            home: WritingCourseHomeScreen(key: ValueKey(dark)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWithAppearance(false);
    expect(find.text('Build confidence to write'), findsOneWidget);
    expect(find.text('5 lessons ready · 0 complete'), findsOneWidget);
    expect(find.text('Introduce yourself'), findsWidgets);
    final lessonGrid = tester.widget<GridView>(
      find.byType(GridView, skipOffstage: false),
    );
    final gridDelegate =
        lessonGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(gridDelegate.crossAxisCount, 3);
    expect(gridDelegate.childAspectRatio, 1);
    await tester.scrollUntilVisible(
      find.text('My daily routine'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('My daily routine'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Complete'),
      -260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(find.text('At the café'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Getting around'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Getting around'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Roleplay'),
      -260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Roleplay'));
    await tester.pumpAndSettle();
    expect(find.text('Make plans with a friend'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Book an appointment'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Book an appointment'), findsWidgets);

    await pumpWithAppearance(true);
    expect(find.text('Build confidence to write'), findsOneWidget);
    expect(find.text('5 lessons ready · 0 complete'), findsOneWidget);
  });

  testWidgets('guided lesson accepts the authored token order', (tester) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final lesson = WritingCourseCatalog.forMode(WritingCourseMode.guided).first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(darkMode: false),
        home: WritingCourseLessonScreen(lesson: lesson),
      ),
    );
    await tester.pumpAndSettle();

    for (final token in lesson.steps.first.tokens) {
      final bankToken = find.text(token).last;
      await tester.ensureVisible(bankToken);
      await tester.tap(bankToken, warnIfMissed: false);
      await tester.pump();
    }
    await tester.tap(find.text('Check sentence'));
    await tester.pumpAndSettle();

    expect(find.text('That sentence is in the right order.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('writing surfaces stay usable on a narrow, enlarged-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const WritingCourseHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(darkMode: false),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: WritingCourseLessonScreen(
          lesson: WritingCourseCatalog.forMode(
            WritingCourseMode.roleplay,
          ).first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('roleplay uses a subtle placeholder and allows redo or next', (
    tester,
  ) async {
    final lesson = WritingCourseCatalog.forMode(
      WritingCourseMode.roleplay,
    ).first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(darkMode: false),
        home: WritingCourseLessonScreen(lesson: lesson),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.decoration?.hintText, 'Write a short reply in French…');
    expect(
      editor.decoration?.hintText,
      isNot(contains(lesson.steps.first.target)),
    );

    await tester.enterText(find.byType(TextField), 'Je voudrais un café');
    await tester.pump();
    await tester.ensureVisible(find.text('Send reply'));
    await tester.tap(find.text('Send reply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Good message.'), findsOneWidget);
    expect(find.text('Redo reply'), findsOneWidget);
    expect(find.text('Next anyway'), findsOneWidget);

    await tester.ensureVisible(find.text('Redo reply'));
    await tester.tap(find.text('Redo reply'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Good message.'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });
}
