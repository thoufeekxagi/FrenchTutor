import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';

Map<String, dynamic> _lesson(List<Map<String, dynamic>> steps) => {
  'id': 't1',
  'title': 'Test lesson',
  'minutes': 4,
  'steps': steps,
};

void main() {
  test('parses every step type', () {
    final lesson = V3Lesson.fromJson(
      _lesson([
        {
          'type': 'explain',
          'id': 'e1',
          'title': 'Title',
          'body': 'Body',
          'examples': [
            {'fr': 'bonjour', 'en': 'hello'},
          ],
        },
        {'type': 'word', 'id': 'w1', 'fr': 'merci', 'en': 'thank you'},
        {'type': 'phrase', 'id': 'p1', 'fr': 'Ça va ?', 'en': 'How are you?'},
        {
          'type': 'choose',
          'id': 'c1',
          'prompt': 'Pick',
          'options': ['a', 'b'],
          'answer': 1,
        },
        {
          'type': 'listen',
          'id': 'l1',
          'fr': 'Il est huit heures.',
          'question': 'When?',
          'options': ['7', '8', '9'],
          'answer': 1,
        },
      ]),
    );
    expect(lesson.steps, hasLength(5));
    expect(lesson.questionCount, 2);
    expect(lesson.steps.first, isA<V3ExplainStep>());
    expect((lesson.steps[3] as V3ChooseStep).answer, 1);
  });

  group('rejects bad lessons with a clear reason', () {
    test('no steps', () {
      expect(
        () => V3Lesson.fromJson(_lesson([])),
        throwsA(isA<FormatException>()),
      );
    });

    test('answer outside the options', () {
      expect(
        () => V3Lesson.fromJson(
          _lesson([
            {
              'type': 'choose',
              'id': 'c1',
              'prompt': 'Pick',
              'options': ['a', 'b'],
              'answer': 2,
            },
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('answer'),
          ),
        ),
      );
    });

    test('fewer than two options', () {
      expect(
        () => V3Lesson.fromJson(
          _lesson([
            {
              'type': 'choose',
              'id': 'c1',
              'prompt': 'Pick',
              'options': ['a'],
              'answer': 0,
            },
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('duplicate step ids', () {
      expect(
        () => V3Lesson.fromJson(
          _lesson([
            {'type': 'word', 'id': 'w1', 'fr': 'a', 'en': 'b'},
            {'type': 'word', 'id': 'w1', 'fr': 'c', 'en': 'd'},
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('repeats step id'),
          ),
        ),
      );
    });

    test('unknown step type', () {
      expect(
        () => V3Lesson.fromJson(
          _lesson([
            {'type': 'video', 'id': 'v1'},
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing French text', () {
      expect(
        () => V3Lesson.fromJson(
          _lesson([
            {'type': 'word', 'id': 'w1', 'en': 'hello'},
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('table step parses and rejects a ragged row', () {
    final ok = V3Lesson.fromJson(
      _lesson([
        {
          'type': 'table',
          'id': 't1',
          'title': 'être',
          'headers': ['Person', 'Form', 'Example'],
          'rows': [
            ['je', 'suis', 'Je suis Sam.'],
            ['tu', 'es', 'Tu es Léa.'],
          ],
          'hear': 2,
        },
      ]),
    );
    expect((ok.steps.single as V3TableStep).rows, hasLength(2));
    expect(
      () => V3Lesson.fromJson(
        _lesson([
          {
            'type': 'table',
            'id': 't1',
            'title': 'x',
            'headers': ['a', 'b'],
            'rows': [
              ['only one'],
            ],
          },
        ]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('every bundled lesson parses, is listed once, and has unit info', () {
    final dir = Directory('assets/content/tcf/lessons');
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    );
    final index =
        (jsonDecode(File('assets/content/tcf/course.json').readAsStringSync())
                as Map)['lessons']
            as List;
    final ids = <String>{};
    for (final f in files) {
      final lesson = V3Lesson.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(ids.add(lesson.id), isTrue, reason: 'duplicate id ${lesson.id}');
      expect(index, contains(f.uri.pathSegments.last), reason: f.path);
      if (!lesson.dev) {
        expect(lesson.unit, isNotEmpty, reason: lesson.id);
        expect(lesson.unitTitle, isNotEmpty, reason: lesson.id);
      }
    }
    expect(
      ids.length,
      index.length,
      reason: 'course.json lists a missing file',
    );
    expect(ids.length, greaterThan(60));
  });
}
