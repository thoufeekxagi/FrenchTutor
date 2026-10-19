import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

/// Every table in the course, with its speakers, lays out without overflow on
/// the smallest phone at double text, an ordinary phone and an iPad.
void main() {
  final entries = <(String, int, V3Lesson)>[];
  for (final f in Directory(
    'assets/content/tcf/lessons',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final lesson = V3Lesson.fromJson(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    );
    for (var i = 0; i < lesson.steps.length; i++) {
      if (lesson.steps[i] is V3TableStep) {
        entries.add((f.uri.pathSegments.last, i, lesson));
      }
    }
  }
  const sizes = {
    'small phone 2x': (Size(320, 568), 2.0),
    'phone': (Size(390, 844), 1.0),
    'iPad': (Size(810, 1080), 1.0),
  };

  for (final size in sizes.entries) {
    testWidgets('all ${entries.length} tables on ${size.key}', (tester) async {
      tester.view.physicalSize = size.value.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final marie = V3FakeMarieSession();
      addTearDown(marie.dispose);
      for (final (file, index, lesson) in entries) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size.value.$1,
                  textScaler: TextScaler.linear(size.value.$2),
                ),
                child: V3LessonPlayer(
                  lesson: lesson,
                  startAt: index,
                  frontier: index,
                  marie: marie,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: '$file step $index');
      }
    });
  }
}
