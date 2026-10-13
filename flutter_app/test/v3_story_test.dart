import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/story/v3_story.dart';

Map<String, dynamic> _story({
  List<Map<String, String>>? sentences,
  Map<String, dynamic>? words,
  List<dynamic>? quiz,
}) => {
  'id': 't1',
  'title': 'Titre',
  'titleEn': 'Title',
  'level': 'A1',
  'minutes': 3,
  'summary': 'A test.',
  'sentences':
      sentences ??
      [
        {'fr': 'Marc dit : « Bonjour ! »', 'en': 'Marc says: "Hello!"'},
      ],
  'words':
      words ??
      {
        'marc': {'en': 'Marc'},
        'dit': {'en': 'says'},
        'bonjour': {'en': 'hello'},
      },
  'keywords': ['bonjour'],
  'quiz':
      quiz ??
      [
        {
          'prompt': 'Who speaks?',
          'options': ['Marc', 'Julie'],
          'answer': 0,
          'explain': 'Marc says hello.',
        },
      ],
};

void main() {
  group('word keys', () {
    test('trim punctuation and lowercase, keep inner apostrophes', () {
      expect(V3Story.keyOf('« Bonsoir'), 'bonsoir');
      expect(V3Story.keyOf('m\'appelle'), 'm\'appelle');
      expect(V3Story.keyOf('l\u2019immeuble.'), 'l\'immeuble');
      expect(V3Story.keyOf('!'), isEmpty);
      expect(V3Story.keyOf('«'), isEmpty);
    });
  });

  group('units', () {
    test('French punctuation sticks to its word, never alone', () {
      final r = V3Story.unitsOf('Marc dit : « Bienvenue ! »');
      expect(r.units.map((u) => u.key), ['marc', 'dit', 'bienvenue']);
      expect(r.units[1].text, 'dit\u00a0:');
      expect(r.units[2].text, '«\u00a0Bienvenue\u00a0!\u00a0»');
    });

    test('raw tokens map to the unit that contains them', () {
      // raw: Marc dit : « Bienvenue ! »  -> 0 1 2 3 4 5 6
      final r = V3Story.unitsOf('Marc dit : « Bienvenue ! »');
      expect(r.rawToUnit, [0, 1, 1, 2, 2, 2, 2]);
    });

    test('a sentence with no punctuation maps one to one', () {
      final r = V3Story.unitsOf('Il est sept heures');
      expect(r.rawToUnit, [0, 1, 2, 3]);
      expect(r.units, hasLength(4));
    });
  });

  group('parsing', () {
    test('parses a valid story', () {
      final s = V3Story.fromJson(_story());
      expect(s.sentences.single.units.map((u) => u.key), [
        'marc',
        'dit',
        'bonjour',
      ]);
      expect(s.quiz.single.answer, 0);
    });

    test('rejects a word with no meaning', () {
      expect(
        () => V3Story.fromJson(
          _story(
            words: {
              'marc': {'en': 'Marc'},
              'dit': {'en': 'says'},
            },
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('bonjour'),
          ),
        ),
      );
    });

    test('rejects an answer outside the options', () {
      expect(
        () => V3Story.fromJson(
          _story(
            quiz: [
              {
                'prompt': 'q',
                'options': ['a', 'b'],
                'answer': 5,
                'explain': 'x',
              },
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a story with no quiz', () {
      expect(
        () => V3Story.fromJson(_story(quiz: [])),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('every bundled story file parses and every word has a meaning', () {
    final dir = Directory('assets/content/tcf/stories');
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    );
    expect(files, isNotEmpty);
    for (final f in files) {
      final story = V3Story.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(story.sentences, isNotEmpty, reason: f.path);
      expect(story.quiz.length, greaterThanOrEqualTo(3), reason: f.path);
    }
  });
}
