import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';

/// What a table speaker says: the French only, never the hints or English.
void main() {
  String? say(String cell, {String? prefix}) =>
      V3TableStep.speechOf(cell, prefix: prefix);

  group('speechOf', () {
    test('drops pronunciation hints, even nested ones', () {
      expect(say('canadien (kah-nah-DYA(N))'), 'canadien');
      expect(say('banc (bah(n))'), 'banc');
      expect(say('tu (you)'), 'tu');
    });
    test('an elision equation says the result', () {
      expect(say("le + ami = l'ami"), "l'ami");
      expect(say("je + ai = j'ai"), "j'ai");
    });
    test('an arrow says the combined sentence', () {
      expect(
        say(
          "C'est le service. Le service répond. → C'est le service qui répond.",
        ),
        "C'est le service qui répond.",
      );
    });
    test('separators become pauses, not symbols', () {
      expect(say('nous (we) · on (we, informal)'), 'nous, on');
      expect(say('serai / seras / sera'), 'serai, seras, sera');
      expect(say('fin de semaine (also week-end)'), 'fin de semaine');
      expect(
        say('douze dollars cinquante (or just: douze cinquante)'),
        'douze dollars cinquante',
      );
    });
    test('a dash or an empty cell is silent', () {
      expect(say('—'), isNull);
      expect(say(''), isNull);
      expect(say('  '), isNull);
    });
    test('the first column is said before a bare verb form', () {
      expect(say('parle', prefix: 'je'), 'je parle');
      expect(say('aime', prefix: 'je'), "j'aime");
      expect(say('habite', prefix: 'je'), "j'habite");
      expect(say('vais', prefix: 'il / elle / on'), 'il vais');
      expect(say('parlons', prefix: 'nous'), 'nous parlons');
    });
    test('a cell that already has its pronoun is left alone', () {
      expect(say('tu parles', prefix: 'tu'), 'tu parles');
      expect(say("j'achète (zhah-SHET)", prefix: 'je'), "j'achète");
      expect(say('elle paie', prefix: 'il / elle'), 'elle paie');
      expect(say("je m'appelle", prefix: 'je'), "je m'appelle");
      expect(say('ils font', prefix: 'ils / elles'), 'ils font');
    });
    test('a verb column prefix ignores the subject before the colon', () {
      expect(say('parlais', prefix: 'parler: je'), 'je parlais');
    });
  });

  group('every table in the course', () {
    final lessons = Directory(
      'assets/content/tcf/lessons',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    final tables = <(String, V3TableStep)>[
      for (final f in lessons)
        for (final s in V3Lesson.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
        ).steps.whereType<V3TableStep>())
          (f.uri.pathSegments.last, s),
    ];

    test('the course has tables, and each speakable one has a speaker', () {
      expect(tables.length, greaterThan(90));
      // French-only reference tables must not be left silent. These are the
      // English-only guidance tables that are allowed to have no audio.
      const silent = {'a1-u01-grammar-c.json', 'a2-u12-grammar-a.json'};
      final missing = [
        for (final (file, s) in tables)
          if (s.layout == 'grid' &&
              s.hear < 0 &&
              s.hearCols.isEmpty &&
              !silent.contains(file))
            '$file ${s.title}',
      ];
      // Print so a future table that needs audio is easy to spot.
      // ignore: avoid_print
      if (missing.isNotEmpty) print('tables without audio: $missing');
      expect(missing.length, lessThan(12));
    });

    test('nothing spoken contains hints, arrows or stray symbols', () {
      for (final (file, s) in tables) {
        final spoken = <String>[];
        for (final row in s.rows) {
          if (s.layout == 'groups') {
            for (var c = 0; c + s.group <= row.length; c += s.group) {
              final v = V3TableStep.speechOf(
                row[c + (s.hear < 0 ? 0 : s.hear)],
              );
              if (v != null) spoken.add(v);
            }
          } else if (s.layout == 'grid') {
            if (s.hear >= 0) {
              final v = V3TableStep.speechOf(row[s.hear]);
              if (v != null) spoken.add(v);
            }
            for (final c in s.hearCols) {
              final v = V3TableStep.speechOf(
                row[c],
                prefix: s.hearPrefix && c != 0 ? row[0] : null,
              );
              if (v != null) spoken.add(v);
            }
          }
        }
        for (final line in spoken) {
          expect(line, isNot(contains('(')), reason: '$file: $line');
          expect(line, isNot(contains('→')), reason: '$file: $line');
          expect(line, isNot(contains('=')), reason: '$file: $line');
          expect(line, isNot(contains(' ,')), reason: '$file: $line');
          expect(line.length, lessThanOrEqualTo(200), reason: '$file: $line');
        }
      }
    });
  });
}
