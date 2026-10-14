import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';

/// Every step of several real lessons must lay out without overflow on a small
/// phone, an iPad (portrait and landscape) and at large text.
void main() {
  final lessons = <String>[
    's0-02',
    's0-06',
    'a1-u01-words-1',
    'a1-u02-grammar-a',
    'a1-u03-dialogues',
    'a1-u04-grammar-b',
    'a1-u04-tcf',
    'a1-u05-reading',
  ];
  final a2UnitOne =
      Directory('assets/content/tcf/lessons')
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.json') &&
                file.uri.pathSegments.last.startsWith('a2-u01-'),
          )
          .map((file) => file.uri.pathSegments.last.replaceFirst('.json', ''))
          .toList()
        ..sort();
  lessons.addAll(a2UnitOne);
  const sizes = {
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'iPad portrait': Size(810, 1080),
    'iPad landscape': Size(1080, 810),
  };

  for (final id in lessons) {
    final lesson = V3Lesson.fromJson(
      jsonDecode(File('assets/content/tcf/lessons/$id.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$id on ${entry.key} at ${scale}x text', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          for (var i = 0; i < lesson.steps.length; i++) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: entry.value,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: V3LessonPlayer(lesson: lesson, startAt: i),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 50));
            expect(
              tester.takeException(),
              isNull,
              reason: '$id step ${lesson.steps[i].id} on ${entry.key} $scale',
            );
          }
        });
      }
    }
  }
}
