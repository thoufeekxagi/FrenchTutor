import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/data/grammar_curriculum_catalog.dart';
import 'package:french_tutor/data/grammar_course_catalog.dart';
import 'package:french_tutor/data/database/grammar_course_lesson_store.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/models/grammar_course_v2.dart';
import 'package:french_tutor/models/grammar_course.dart';
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

  testWidgets('Grammar home uses session cards and mode picker', (
    tester,
  ) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    tester.binding.window.physicalSizeTestValue = const Size(390, 844);
    tester.binding.window.devicePixelRatioTestValue = 1;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: false),
          home: GrammarV2HomeScreen(generatedSessions: const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build confidence with grammar'), findsOneWidget);
    expect(find.text('Guided'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Roleplay'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -520));
    await tester.pump();
    expect(find.byType(GridView, skipOffstage: false), findsOneWidget);
    final grid = tester.widget<GridView>(
      find.byType(GridView, skipOffstage: false),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(delegate.childAspectRatio, 1);
    expect(
      find.text('5 connected steps', skipOffstage: false),
      findsNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });

  test('the first reserve is three sessions per mode with bounded steps', () {
    for (final mode in GrammarV2Mode.values) {
      final sessions = grammarCourseStarterSessions
          .where((session) => session.mode == mode)
          .toList();
      expect(sessions, hasLength(3), reason: mode.name);
      for (final session in sessions) {
        expect(session.steps.length, mode == GrammarV2Mode.roleplay ? 4 : 5);
        expect(GrammarCourseValidator.validate(session), same(session));
      }
    }
  });

  testWidgets('Grammar lesson has no typing and supports all three modes', (
    tester,
  ) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    for (final mode in GrammarV2Mode.values) {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final session = grammarCourseStarterSessions.firstWhere(
        (item) => item.mode == mode,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.themeData(darkMode: false),
            home: GrammarV2LessonScreen(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: mode.label);
      expect(find.textContaining(mode.label.toUpperCase()), findsOneWidget);
      if (mode == GrammarV2Mode.guided) {
        expect(
          find.byIcon(Icons.translate_rounded, skipOffstage: false),
          findsOneWidget,
        );
        // The meaning of the sentence is part of the guided blank card from
        // the start, not only after the answer is checked.
        expect(
          find.text(session.steps.first.promptEnglish, skipOffstage: false),
          findsOneWidget,
        );
      } else if (mode == GrammarV2Mode.complete) {
        expect(find.text('Learn the pattern'), findsOneWidget);
      } else {
        expect(find.text('Reply in the scene'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('each Grammar mode checks its frozen answer', (tester) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    Future<void> pumpMode(GrammarV2Mode mode) async {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final session = grammarCourseStarterSessions.firstWhere(
        (item) => item.mode == mode,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.themeData(darkMode: false),
            home: GrammarV2LessonScreen(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpMode(GrammarV2Mode.guided);
    final guidedSession = grammarCourseStarterSessions.firstWhere(
      (session) => session.mode == GrammarV2Mode.guided,
    );
    final guidedChoice = find.text(guidedSession.steps.first.answer).last;
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
    final completeSession = grammarCourseStarterSessions.firstWhere(
      (session) => session.mode == GrammarV2Mode.complete,
    );
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I see the pattern'));
    await tester.pumpAndSettle();
    final transformation = find.text(completeSession.steps[2].target).last;
    await tester.ensureVisible(transformation);
    await tester.tap(transformation);
    await tester.pump();
    await tester.tap(find.text('Check transformation'));
    await tester.pump();
    expect(
      find.textContaining('Correct.', skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.text('Next stage'));
    await tester.pumpAndSettle();
    final repair = find.text(completeSession.steps[3].target).last;
    await tester.ensureVisible(repair);
    await tester.tap(repair);
    await tester.pump();
    await tester.tap(find.text('Check repair'));
    await tester.pump();
    expect(
      find.textContaining('Correct.', skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.text('Next stage'));
    await tester.pumpAndSettle();
    for (final word in completeSession.steps[4].tokens) {
      final wordFinder = find.widgetWithText(ActionChip, word).last;
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
    final roleplaySession = grammarCourseStarterSessions.firstWhere(
      (session) => session.mode == GrammarV2Mode.roleplay,
    );
    expect(roleplaySession.steps, hasLength(4));
    expect(find.text('Reply in the scene'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Check reply'), findsNothing);
  });

  testWidgets('finishing the final step persists the session checkmark', (
    tester,
  ) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final session = grammarCourseStarterSessions.first;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: false),
          home: GrammarV2LessonScreen(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < session.steps.length; index++) {
      final answer = find.text(session.steps[index].answer).last;
      await tester.ensureVisible(answer);
      await tester.tap(answer);
      await tester.pump();
      await tester.ensureVisible(find.text('Check form'));
      await tester.tap(find.text('Check form'));
      await tester.pump();
      final next = index == session.steps.length - 1
          ? find.text('Finish session')
          : find.text('Next step');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }

    final store = LearningStore(db);
    expect(store.lessonStatus(session.progressId).status, 'completed');
    for (var index = 0; index < session.steps.length; index++) {
      expect(
        store.lessonStatus('${session.progressId}_step_$index').status,
        'completed',
      );
    }
  });

  test('Grammar persistence keeps steps nested inside one session row', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = GrammarCourseLessonStore(db);
    final session = grammarCourseStarterSessions.first;

    expect(session.steps, hasLength(5));
    expect(store.insertGenerated(session), isTrue);
    expect(store.insertGenerated(session), isFalse);

    final saved = store.list(
      mode: session.mode,
      level: session.level,
      tense: session.tense,
    );
    expect(saved, hasLength(1));
    expect(saved.single.id, session.id);
    expect(saved.single.steps, hasLength(5));
  });
}
