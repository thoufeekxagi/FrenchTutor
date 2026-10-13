import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

/// A live call with a long reply must never squeeze the lesson off a small
/// phone, on any kind of step, and must follow the learner to the next step.
void main() {
  const reply =
      'Good question. In French the last letter is usually silent, so sortie '
      'ends on the TEE sound. Listen: sortie. Now you try it, slowly, and I will '
      'tell you exactly which sound to adjust, one thing at a time.';
  final lesson = V3Lesson.fromJson(
    jsonDecode(
          File(
            'assets/content/tcf/lessons/a1-u02-grammar-a.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  final words = V3Lesson.fromJson(
    jsonDecode(
          File(
            'assets/content/tcf/lessons/a1-u01-words-1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  const sizes = {
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'iPad portrait': Size(810, 1080),
    'iPad landscape': Size(1080, 810),
  };

  for (final entry in sizes.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('lesson with a live call, ${entry.key}, ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        V3MarieSession.debugLog.clear();
        final marie = V3FakeMarieSession();
        addTearDown(marie.dispose);

        for (final (l, label) in [(words, 'word'), (lesson, 'table')]) {
          for (var i = 0; i < l.steps.length; i += 3) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: entry.value,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: V3LessonPlayer(lesson: l, startAt: i, marie: marie),
                  ),
                ),
              ),
            );
            if (!marie.isBusy) {
              final f = marie.toggle(
                tester.element(find.byType(V3LessonPlayer)),
              );
              await tester.pump(const Duration(milliseconds: 600));
              await f;
            }
            marie.debugSay(reply);
            await tester.pump(const Duration(seconds: 3));
            expect(
              tester.takeException(),
              isNull,
              reason: '$label step ${l.steps[i].id}, ${entry.key} ${scale}x',
            );
            // The lesson itself keeps a usable area to read.
            final lessonArea = tester.getSize(find.byType(ListView).first);
            expect(
              lessonArea.height,
              greaterThan(entry.value.height > 700 ? 250 : 60),
              reason: 'lesson squeezed to ${lessonArea.height}',
            );
          }
        }
        await marie.end();
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  }

  testWidgets('tapping a speaker asks Marie to say that exact word', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    V3MarieSession.debugLog.clear();
    final marie = V3FakeMarieSession();
    addTearDown(marie.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V3LessonPlayer(lesson: words, marie: marie),
        ),
      ),
    );
    final first = (words.steps.first as V3WordStep).spoken;
    await tester.tap(find.bySemanticsLabel('Hear $first').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(V3MarieSession.debugLog, contains('speak:$first'));
    expect(marie.muted, isTrue, reason: 'a speaker tap must not open the mic');
    expect(find.byKey(const ValueKey('marie.dock')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await marie.end();
    await tester.pump(const Duration(milliseconds: 100));
    semantics.dispose();
  });
}
