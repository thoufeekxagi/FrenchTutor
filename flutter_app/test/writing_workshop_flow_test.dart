import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/screens/lessons/writing_workshop_screen.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/services/lesson_agent_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  testWidgets('initial writing submission renders feedback exactly once', (
    WidgetTester tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    var gradingCalls = 0;
    final gradingResult = Completer<WritingFeedback>();
    final task = WritingTask(
      id: 'writing-test',
      type: 'micro',
      title: 'My family',
      promptFr: 'Écris une phrase sur ta famille.',
      promptEn: 'Write one sentence about your family.',
      minWords: 5,
      targetConnectors: const [],
      rubricHints: const ['Use one family word.'],
      levelBand: 'A1',
    );
    final feedback = WritingFeedback(
      scoreOutOf10: 7.5,
      strengths: const ['The sentence communicates a clear idea.'],
      corrections: const [
        (original: 'my fam', fixed: 'ma famille', why: 'Use the French noun.'),
      ],
      connectorFeedback: 'Keep one clear idea in each short sentence.',
      improvedVersion: 'Je suis content avec ma famille.',
      nextSteps: const ['Use one French noun in your next sentence.'],
      scoreBreakdown: const {
        'task_completion': 8.0,
        'grammar': 7.0,
        'vocabulary': 7.0,
        'coherence': 8.0,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          writingFeedbackGraderProvider.overrideWithValue(({
            required WritingTask task,
            required String submission,
            required String levelBand,
          }) async {
            gradingCalls++;
            return gradingResult.future;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.themeData(),
          home: WritingWorkshopScreen(task: task),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build my answer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'je suis content my fam');
    await tester.tap(find.text('Write freely'));
    await tester.pumpAndSettle();

    expect(find.text('Submit for feedback'), findsOneWidget);
    await tester.tap(find.text('Submit for feedback'));
    await tester.pump();

    expect(find.text('Preparing your feedback'), findsOneWidget);
    expect(find.text('YOUR SUBMISSION'), findsOneWidget);
    expect(find.text('je suis content my fam'), findsOneWidget);

    gradingResult.complete(feedback);
    await tester.pump();
    expect(find.text('WRITING SCORE'), findsOneWidget);
    expect(find.text('7.5 / 10'), findsOneWidget);
    expect(gradingCalls, 1);
  });
}
