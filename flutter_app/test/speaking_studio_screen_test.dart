import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/speak/speaking_studio_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  testWidgets('Home recovers when its adaptive plan is missing', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: true),
          home: const SpeakingStudioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Your next session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home quick start leads with Review, Warm-up, and Live tutor', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: true),
          home: const SpeakingStudioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Warm-up'), findsOneWidget);
    expect(find.text('Live tutor'), findsOneWidget);
    expect(find.text('Past lessons'), findsOneWidget);
    expect(find.text('Next lesson'), findsOneWidget);
    expect(find.text('Choose your style'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Explore starts with a Report shortcut that opens the weekly view',
    (tester) async {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.themeData(darkMode: true),
            home: const SpeakingStudioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
      await tester.pumpAndSettle();

      final report = find.text('Report');
      final listening = find.text('Listening');
      expect(report, findsOneWidget);
      expect(listening, findsOneWidget);
      expect(
        tester.getTopLeft(report).dx,
        lessThan(tester.getTopLeft(listening).dx),
      );

      await tester.tap(report);
      await tester.pumpAndSettle();
      expect(find.text('Your French this week'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home keeps the authored route stable until a lesson completes', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final profileStore = LearningStore(db);
    final profile = profileStore.profile()
      ..goal = 'everyday'
      ..level = 'a2';
    profileStore.saveProfile(profile);
    final store = AdaptiveCourseStore(db);
    final initial = store.ensureCurrentPlan(profile);

    db.execute(
      '''INSERT INTO sessions
         (id, started_at, ended_at, summary, topic, content_key, vocabulary,
          stage, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        'practice-evidence',
        '2026-09-04T20:00:00.000Z',
        '2026-09-04T20:05:00.000Z',
        'Practised ordering at a café.',
        'At the café',
        'practice_cafe',
        '[]',
        'free_talk',
        '2026-09-04T20:05:00.000Z',
      ],
    );
    expect(store.currentPlan(profile)?.id, initial.id);
    // Foundation (1-5) and Unit 2 (6-11) are authored, fixed content shared
    // by every learner. Merely reopening Home must not append a random lesson;
    // the owning lesson-completion flow advances its same-skill lane.
    for (final session in initial.sessions) {
      store.markCompleted(session.contentKey);
    }
    final expanded = store.ensureCurrentPlan(profile);
    expect(expanded.id, initial.id);
    expect(expanded.sessions, hasLength(11));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: true),
          home: const SpeakingStudioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final refreshed = store.currentPlan(profile);
    expect(refreshed?.id, initial.id);
    expect(find.text('Your next session'), findsOneWidget);
    expect(find.text('Your next lesson will appear here.'), findsNothing);
    expect(find.text('RECENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
