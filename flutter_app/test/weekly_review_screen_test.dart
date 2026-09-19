import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/home/weekly_review_screen.dart';

void main() {
  testWidgets('weekly review exposes four swipeable views without overflow', (
    tester,
  ) async {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: WeeklyReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your French this week'), findsOneWidget);
    expect(find.text('Your week starts here.'), findsOneWidget);

    for (final title in const [
      'Words from your week',
      'Corrections worth keeping',
      'Your next best step',
    ]) {
      await tester.drag(find.byType(PageView), const Offset(-330, 0));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      final exception = tester.takeException();
      expect(exception, isNull, reason: '$title: $exception');
    }
  });
}
