// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/app.dart';
import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/home/daily_pathway_widget.dart';
import 'package:french_tutor/widgets/speaking_session_result.dart';

void main() {
  setUpAll(() async {
    // supabase_flutter's session storage reads shared_preferences under the
    // hood — the plugin has no platform-channel implementation in the test
    // sandbox, so it needs its mock seeded first (same pattern used in
    // mic_mode_test.dart / tutor_persona_test.dart).
    SharedPreferences.setMockInitialValues({});
    // AuthGate touches Supabase.instance on every build (auth is now the
    // first gate, ahead of onboarding) — a fake-but-valid config is enough
    // for a fresh, session-less client; no network call is made unless a
    // sign-in method is actually invoked, which this file never does.
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  testWidgets('first run opens onboarding; sign-in waits until after it', (
    WidgetTester tester,
  ) async {
    // Build the real app against an isolated local database.
    final db = sqlite3.openInMemory();

    // Ensure the native database allocation is released after the test.
    addTearDown(db.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const FrenchTutorApp(),
      ),
    );

    // Let theme and onboarding layout finish their first frame.
    await tester.pumpAndSettle();

    // Deliberate order: a fresh learner experiences the product first
    // (goal/level/tutor onboarding) and is asked to create an account only
    // at the END of onboarding — never an account wall up front.
    expect(find.text('What should French unlock for you?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('today plan exposes one recommended next action', (
    WidgetTester tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(),
          home: const Scaffold(body: DailyPathwayWidget()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('Build today’s vocabulary'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Grammar'), findsNothing);
  });

  testWidgets('completed speaking result reports real evidence', (
    WidgetTester tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: SpeakingSessionResultView(
          durationSeconds: 95,
          learnerTurns: 6,
          meetsCompletionThreshold: true,
          isDailyPath: true,
          onDone: () => finished = true,
        ),
      ),
    );

    expect(find.text('Practice saved'), findsOneWidget);
    expect(find.text('1:35'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('Daily path updated'), findsOneWidget);

    await tester.tap(find.text('Done'));
    expect(finished, isTrue);
  });

  testWidgets('short speaking result does not claim completion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: SpeakingSessionResultView(
          durationSeconds: 12,
          learnerTurns: 1,
          meetsCompletionThreshold: false,
          isDailyPath: true,
          onDone: () {},
        ),
      ),
    );

    expect(find.text('Good start—keep going'), findsOneWidget);
    expect(
      find.textContaining('Nothing has been marked complete'),
      findsOneWidget,
    );
    expect(find.text('Practice saved'), findsNothing);
  });
}
