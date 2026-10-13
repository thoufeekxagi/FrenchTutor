import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Going back inside a lesson, replaying a finished one, and the rule that
/// real progress (Resume) never moves backwards.
void main() {
  final lesson = V3Lesson.fromJson(
    jsonDecode(
          File(
            'assets/content/tcf/lessons/a1-u01-words-1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  bool isQ(V3Step s) => s is V3ChooseStep || s is V3ListenStep;
  // First index where this and the next two steps are plain (no question).
  final plain = [
    for (var i = 0; i < lesson.steps.length - 3; i++)
      if (!isQ(lesson.steps[i]) &&
          !isQ(lesson.steps[i + 1]) &&
          !isQ(lesson.steps[i + 2]))
        i,
  ].first;
  final q = lesson.steps.indexWhere(isQ);
  final lastIndex = lesson.steps.length - 1;

  Future<V3FakeMarieSession> pump(
    WidgetTester tester, {
    int startAt = 0,
    int frontier = 0,
    bool reviewAll = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final marie = V3FakeMarieSession();
    addTearDown(marie.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V3LessonPlayer(
            lesson: lesson,
            startAt: startAt,
            frontier: frontier,
            reviewAll: reviewAll,
            marie: marie,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return marie;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder onStep(int i) => find.byKey(ValueKey('step-${lesson.steps[i].id}'));
  Future<Map<String, int>> positions(WidgetTester tester) async {
    await tester.pump();
    return (await tester.runAsync(V3Progress.positions))!;
  }

  // The double-tap guard uses the real clock, which tests cannot move.
  setUpAll(() => V3LessonPlayer.advanceGuard = Duration.zero);
  tearDownAll(
    () => V3LessonPlayer.advanceGuard = const Duration(milliseconds: 450),
  );
  setUp(() {
    V3Progress.resetQueueForTest();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no Previous button on the first step', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('lesson.back')), findsNothing);
    expect(find.byKey(const ValueKey('lesson.jumpToFrontier')), findsNothing);
  });

  testWidgets('going back shows the earlier step and keeps real progress', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'v3_lesson_position': ['${lesson.id}:${plain + 2}'],
    });
    await pump(tester, startAt: plain + 2, frontier: plain + 2);
    expect(onStep(plain + 2), findsOneWidget);
    expect(find.textContaining('Reviewing'), findsNothing);

    await tapKey(tester, 'lesson.back');
    await tapKey(tester, 'lesson.back');
    expect(onStep(plain), findsOneWidget);
    expect(
      find.textContaining('Your progress is at step ${plain + 3}'),
      findsOneWidget,
    );
    expect(
      (await positions(tester))[lesson.id],
      plain + 2,
      reason: 'going back must never lower where Resume returns',
    );
  });

  testWidgets('Go to step N returns to where progress really is', (
    tester,
  ) async {
    await pump(tester, startAt: plain + 2, frontier: plain + 2);
    await tapKey(tester, 'lesson.back');
    await tapKey(tester, 'lesson.back');
    await tapKey(tester, 'lesson.jumpToFrontier');
    expect(onStep(plain + 2), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson.jumpToFrontier')), findsNothing);
  });

  testWidgets(
    'walking forward through reviewed steps does not rewrite progress',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'v3_lesson_position': ['${lesson.id}:${plain + 2}'],
      });
      await pump(tester, startAt: plain, frontier: plain + 2);
      await tapKey(tester, 'lesson.continue');
      expect(onStep(plain + 1), findsOneWidget);
      expect((await positions(tester))[lesson.id], plain + 2);
    },
  );

  testWidgets('moving past the frontier moves real progress forward', (
    tester,
  ) async {
    await pump(tester, startAt: plain, frontier: plain);
    await tapKey(tester, 'lesson.continue');
    await tapKey(tester, 'lesson.continue');
    // Back one step: the lesson now knows progress is two steps further on.
    await tapKey(tester, 'lesson.back');
    expect(onStep(plain + 1), findsOneWidget);
    expect(
      find.textContaining('Your progress is at step ${plain + 3}'),
      findsOneWidget,
    );
  });

  testWidgets('a finished lesson replays from the top and changes nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'v3_completed_lessons': [lesson.id],
    });
    await pump(tester, startAt: 0, frontier: 0, reviewAll: true);
    expect(find.textContaining('Reviewing'), findsNothing);
    await tapKey(tester, 'lesson.continue');
    await tapKey(tester, 'lesson.continue');
    expect(onStep(2), findsOneWidget);
    await tapKey(tester, 'lesson.back');
    expect(onStep(1), findsOneWidget);
    expect(await positions(tester), isEmpty);
  });

  testWidgets('an answered question is still answered when you come back', (
    tester,
  ) async {
    final step = lesson.steps[q];
    final answer = step is V3ChooseStep
        ? step.answer
        : (step as V3ListenStep).answer;
    await pump(tester, startAt: q, frontier: q);
    await tapKey(tester, 'lesson.option.$answer');
    await tapKey(tester, 'lesson.check');
    expect(find.text('Correct'), findsOneWidget);
    await tapKey(tester, 'lesson.continue');
    await tapKey(tester, 'lesson.back');
    expect(onStep(q), findsOneWidget);
    expect(
      find.text('Correct'),
      findsOneWidget,
      reason: 'shown, not asked again',
    );
    expect(find.byKey(const ValueKey('lesson.check')), findsNothing);
  });

  testWidgets('a question from earlier can be skipped when reviewing', (
    tester,
  ) async {
    await pump(tester, startAt: q, frontier: lastIndex);
    expect(find.byKey(const ValueKey('lesson.skipQuestion')), findsOneWidget);
    await tapKey(tester, 'lesson.skipQuestion');
    expect(onStep(q + 1), findsOneWidget);
  });

  testWidgets('the question you are working on right now cannot be skipped', (
    tester,
  ) async {
    await pump(tester, startAt: q, frontier: q);
    expect(find.byKey(const ValueKey('lesson.skipQuestion')), findsNothing);
  });

  testWidgets('Previous is a real tap target', (tester) async {
    await pump(tester, startAt: plain + 1, frontier: plain + 1);
    final size = tester.getSize(find.byKey(const ValueKey('lesson.back')));
    expect(size.shortestSide, greaterThanOrEqualTo(44));
  });
}
