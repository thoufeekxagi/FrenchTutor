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

  testWidgets('Home keeps the batch stable and uses evidence on refill', (
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
    for (final session in initial.sessions.take(9)) {
      store.markCompleted(session.contentKey);
    }
    final expanded = store.ensureCurrentPlan(profile);
    expect(expanded.id, initial.id);
    expect(expanded.sessions, hasLength(15));
    expect(
      expanded.sessions
          .skip(10)
          .every(
            (session) => session.sourceSessionIds.contains('practice-evidence'),
          ),
      isTrue,
    );

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
    expect(tester.takeException(), isNull);
  });
}
