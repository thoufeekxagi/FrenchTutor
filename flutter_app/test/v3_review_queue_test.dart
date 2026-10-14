import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/models/srs_state.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/review/v3_review_queue.dart';

/// Daily review follows the learner's own lessons: it grows as they learn and
/// never shows a word they have not met.
void main() {
  V3Lesson load(String id) => V3Lesson.fromJson(
    jsonDecode(File('assets/content/tcf/lessons/$id.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final w1 = load('a1-u01-words-1');
  final w2 = load('a1-u01-words-2');
  final course = [w1, w2];
  List<String> words(V3Lesson l) => [
    for (final s in l.steps)
      if (s is V3WordStep) s.fr,
  ];

  test('a new learner has nothing to review', () {
    expect(V3ReviewQueue.learnedWords(course, {}, {}), isEmpty);
  });

  test('a finished lesson contributes all of its words, in order', () {
    final learned = V3ReviewQueue.learnedWords(course, {w1.id}, {});
    expect(learned.map((e) => e.fr).toList(), words(w1));
  });

  test('an unfinished lesson contributes only the words reached', () {
    final firstWordIndex = w1.steps.indexWhere((s) => s is V3WordStep);
    final secondWordIndex = w1.steps.indexWhere(
      (s) => s is V3WordStep,
      firstWordIndex + 1,
    );
    final learned = V3ReviewQueue.learnedWords(course, {}, {
      w1.id: firstWordIndex,
    });
    expect(learned.map((e) => e.fr).toList(), [words(w1).first]);
    final more = V3ReviewQueue.learnedWords(course, {}, {
      w1.id: secondWordIndex,
    });
    expect(more.length, 2);
  });

  test('it grows as lessons are finished', () {
    final one = V3ReviewQueue.learnedWords(course, {w1.id}, {}).length;
    final two = V3ReviewQueue.learnedWords(course, {w1.id, w2.id}, {}).length;
    expect(two, greaterThan(one));
  });

  test('a word taught in two lessons is listed once', () {
    final twice = V3ReviewQueue.learnedWords([w1, w1], {w1.id}, {});
    expect(twice.length, words(w1).toSet().length);
  });

  test('ids are stable and case-insensitive', () {
    expect(V3ReviewQueue.idFor(' Bonjour '), 'v3:bonjour');
  });

  group('today\'s queue', () {
    final now = DateTime(2027, 1, 10, 9);
    List<VocabEntry> learned(int n) => [
      for (var i = 0; i < n; i++)
        VocabEntry(id: 'v3:w$i', en: 'e$i', fr: 'w$i', phonetic: ''),
    ];
    SRSState due(String id, DateTime at) => SRSState(entryId: id, dueAt: at);

    test('new words come in the order they were taught, within the budget', () {
      final q = V3ReviewQueue.build(
        learned: learned(10),
        states: {},
        now: now,
        targetSize: 5,
        newBudget: 3,
      );
      expect(q.map((e) => e.fr).toList(), ['w0', 'w1', 'w2']);
    });

    test('due words come first, longest overdue first', () {
      final q = V3ReviewQueue.build(
        learned: learned(6),
        states: {
          'v3:w1': due('v3:w1', now.subtract(const Duration(days: 1))),
          'v3:w3': due('v3:w3', now.subtract(const Duration(days: 5))),
        },
        now: now,
        targetSize: 4,
        newBudget: 20,
      );
      expect(q.map((e) => e.fr).toList(), ['w3', 'w1', 'w0', 'w2']);
    });

    test('a word reviewed and not yet due is left alone', () {
      final q = V3ReviewQueue.build(
        learned: learned(3),
        states: {'v3:w0': due('v3:w0', now.add(const Duration(days: 2)))},
        now: now,
        targetSize: 5,
        newBudget: 20,
      );
      expect(q.map((e) => e.fr).toList(), ['w1', 'w2']);
    });

    test('the size limit holds even when more is due', () {
      final states = {
        for (var i = 0; i < 8; i++)
          'v3:w$i': due('v3:w$i', now.subtract(Duration(days: i + 1))),
      };
      final q = V3ReviewQueue.build(
        learned: learned(8),
        states: states,
        now: now,
        targetSize: 5,
        newBudget: 20,
      );
      expect(q.length, 5);
      expect(q.first.fr, 'w7');
    });

    test('nothing new today and nothing due is an empty, honest queue', () {
      final q = V3ReviewQueue.build(
        learned: learned(4),
        states: {},
        now: now,
        targetSize: 5,
        newBudget: 0,
      );
      expect(q, isEmpty);
    });

    test('an ignored (null dueAt) state is not due and not new', () {
      final q = V3ReviewQueue.build(
        learned: learned(2),
        states: {'v3:w0': SRSState(entryId: 'v3:w0')},
        now: now,
        targetSize: 5,
        newBudget: 20,
      );
      expect(q.map((e) => e.fr).toList(), ['w1']);
    });
  });
}
