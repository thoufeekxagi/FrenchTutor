import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class _Recording extends V3FakeMarieSession {
  final asked = <List<String>>[];
  @override
  void prefetch(List<String> lines) => asked.add(lines);
}

/// The speaker clips for the next five steps are asked for once, and never
/// again for steps that were already covered.
void main() {
  final lesson = V3Lesson.fromJson(
    jsonDecode(
          File(
            'assets/content/tcf/lessons/a1-u01-words-1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  final last = lesson.steps.length - 1;

  Future<_Recording> pump(WidgetTester tester, {int startAt = 0}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final marie = _Recording();
    addTearDown(marie.dispose);
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [learningStoreProvider.overrideWithValue(LearningStore(db))],
        child: MaterialApp(
          home: V3LessonPlayer(
            lesson: lesson,
            startAt: startAt,
            frontier: startAt,
            marie: marie,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return marie;
  }

  setUpAll(() => V3LessonPlayer.advanceGuard = Duration.zero);
  tearDownAll(
    () => V3LessonPlayer.advanceGuard = const Duration(milliseconds: 450),
  );
  setUp(() {
    V3Progress.resetQueueForTest();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opening a lesson asks once for this step and the next five', (
    tester,
  ) async {
    final marie = await pump(tester);
    expect(marie.asked, hasLength(1));
    // Steps 0 to 5 are words: a word and an example each.
    expect(marie.asked.single, hasLength(12));
    expect(marie.asked.single, contains('Bonjour, madame.'));
    expect(
      marie.asked.single,
      isNot(contains('Bonjour, monsieur.')),
      reason: 'step 6 is outside the window',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(marie.asked, hasLength(1), reason: 'no repeat asks');
  });

  testWidgets('moving on asks only for the one step that came into range', (
    tester,
  ) async {
    final marie = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lesson.continue')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(marie.asked, hasLength(2));
    expect(marie.asked.last, ['monsieur', 'Bonjour, monsieur.']);
  });

  testWidgets('going back never asks again', (tester) async {
    final marie = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lesson.continue')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('lesson.back')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(marie.asked, hasLength(2));
  });

  testWidgets('near the end it asks once for what is left, then never again', (
    tester,
  ) async {
    final marie = await pump(tester, startAt: last - 2);
    expect(marie.asked, hasLength(1));
    expect(marie.asked.single, ['bonsoir', 'oui']);
    await tester.pump(const Duration(seconds: 1));
    expect(marie.asked, hasLength(1));
  });
}
