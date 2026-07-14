// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/app.dart';
import 'package:french_tutor/providers/database_provider.dart';

void main() {
  testWidgets('first run opens ParleSprint onboarding', (
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

    // Verify that a fresh learner reaches the intended first question.
    expect(find.text('What brings you to French?'), findsOneWidget);
  });
}
