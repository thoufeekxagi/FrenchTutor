import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real progress: where Resume goes. Going back to review, replaying and
/// reopening must never move it backwards or sideways.
void main() {
  V3Lesson load(String id) => V3Lesson.fromJson(
    jsonDecode(File('assets/content/tcf/lessons/$id.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final course = [
    for (final id in [
      'a1-u01-words-1',
      'a1-u01-words-2',
      'a1-u01-words-3',
      'a1-u01-words-4',
    ])
      load(id),
  ];
  final ids = course.map((l) => l.id).toList();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('frontier', () {
    test('only ever moves forward', () async {
      await V3Progress.advanceFrontier(ids[0], 4);
      await V3Progress.advanceFrontier(ids[0], 2);
      await V3Progress.advanceFrontier(ids[0], 9);
      await V3Progress.advanceFrontier(ids[0], 5);
      expect((await V3Progress.positions())[ids[0]], 9);
    });

    test('step zero is not progress', () async {
      await V3Progress.advanceFrontier(ids[0], 0);
      expect(await V3Progress.positions(), isEmpty);
      expect(await V3Progress.lastActive(), isNull);
    });

    test(
      'a finished lesson never gets a frontier (a replay is practice)',
      () async {
        await V3Progress.markDone(ids[0]);
        await V3Progress.advanceFrontier(ids[0], 5);
        expect(await V3Progress.positions(), isEmpty);
        expect(await V3Progress.lastActive(), isNull);
      },
    );

    test('finishing clears the frontier and the active lesson', () async {
      await V3Progress.advanceFrontier(ids[0], 5);
      expect(await V3Progress.lastActive(), ids[0]);
      await V3Progress.markDone(ids[0]);
      expect(await V3Progress.positions(), isEmpty);
      expect(await V3Progress.lastActive(), isNull);
      expect(await V3Progress.completed(), {ids[0]});
    });

    test('each lesson keeps its own frontier', () async {
      await V3Progress.advanceFrontier(ids[0], 3);
      await V3Progress.advanceFrontier(ids[1], 7);
      expect(await V3Progress.positions(), {ids[0]: 3, ids[1]: 7});
      expect(await V3Progress.lastActive(), ids[1]);
    });

    test('progress saved by the previous version still loads', () async {
      SharedPreferences.setMockInitialValues({
        'v3_lesson_position': ['${ids[1]}:6'],
      });
      expect((await V3Progress.positions())[ids[1]], 6);
    });
  });

  group('completed order', () {
    test('replaying an old lesson does not move the path', () async {
      await V3Progress.markDone(ids[0]);
      await V3Progress.markDone(ids[1]);
      expect(await V3Progress.lastCompleted(), ids[1]);
      await V3Progress.markDone(ids[0]); // replay finished again
      expect(await V3Progress.lastCompleted(), ids[1]);
    });
  });

  group('pickNext (where Resume goes)', () {
    V3Lesson? pick({
      Set<String> done = const {},
      Map<String, int> frontier = const {},
      String? active,
      String? lastCompleted,
    }) => V3Progress.pickNext(
      course,
      done,
      frontier,
      active: active,
      lastCompleted: lastCompleted,
    );

    test('a new learner starts at the first lesson', () {
      expect(pick()!.id, ids[0]);
    });

    test('the lesson last worked on wins, even if an earlier one is open', () {
      expect(
        pick(done: {}, frontier: {ids[0]: 3, ids[2]: 5}, active: ids[2])!.id,
        ids[2],
      );
    });

    test('an active lesson with no real progress is ignored', () {
      expect(pick(active: ids[2], frontier: {})!.id, ids[0]);
    });

    test('an active lesson that is already finished is ignored', () {
      expect(
        pick(done: {ids[2]}, frontier: {ids[2]: 4}, active: ids[2])!.id,
        ids[0],
      );
    });

    test('the path carries on after the lesson finished last', () {
      expect(pick(done: {ids[0], ids[2]}, lastCompleted: ids[2])!.id, ids[3]);
    });

    test('it wraps back to anything left behind', () {
      expect(
        pick(done: {ids[1], ids[2], ids[3]}, lastCompleted: ids[3])!.id,
        ids[0],
      );
    });

    test('everything finished means nothing next', () {
      expect(pick(done: ids.toSet(), lastCompleted: ids.last), isNull);
    });

    test('an unknown lesson id from an older course is ignored', () {
      expect(pick(active: 'gone', frontier: {'gone': 4})!.id, ids[0]);
      expect(pick(lastCompleted: 'gone')!.id, ids[0]);
    });
  });
}
