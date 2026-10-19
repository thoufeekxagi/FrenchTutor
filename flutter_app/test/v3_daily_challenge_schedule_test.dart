import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/daily_challenge/v3_daily_challenge.dart';

/// The prepared 7-day schedule (not published). Each package must render in
/// the app exactly as the Edge Function would return it: answer keys removed,
/// a placeholder answer index, and a real answer key kept server-side.
void main() {
  final dir = Directory('../content/tcf/daily_challenges/schedule_2026-10-18');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  test('28 packages: seven days for each of A1, A2, B1 and B2', () {
    expect(files.length, 28 + 0 /* schedule.csv is not .json */);
    final seen = <String>{};
    for (final f in files) {
      final p = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      seen.add('${p['level']}|${p['available_on']}');
    }
    for (final level in ['a1', 'a2', 'b1', 'b2']) {
      for (var d = 18; d <= 24; d++) {
        expect(seen, contains('$level|2026-10-$d'), reason: '$level $d');
      }
    }
  });

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    test(
      '$name renders like the server response and keeps answers private',
      () {
        final p = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final lesson = (p['lesson'] as Map).cast<String, dynamic>();
        final steps = (lesson['steps'] as List).cast<Map<String, dynamic>>();
        expect(steps.length, inInclusiveRange(2, 6));
        expect((p['steps'] as List).length, steps.length);

        // What the app receives: answers replaced by a placeholder.
        final publicSteps = [
          for (final s in steps)
            {
              ...s,
              if (s['type'] == 'choose' || s['type'] == 'listen') 'answer': 0,
            },
        ];
        final response = {
          'id': 'test',
          'level': p['level'],
          'primary_skill': p['primary_skill'],
          'title': p['title'],
          'summary': p['summary'],
          'minutes': p['minutes'],
          'steps': p['steps'],
          'lesson': {...lesson, 'steps': publicSteps},
          'attempt': {'id': 'attempt', 'status': 'started', 'current_step': 0},
        };
        final challenge = V3DailyChallenge.fromJson(response, remote: true);
        expect(challenge.lesson.steps.length, steps.length);
        expect(challenge.remote, isTrue);

        // The real key is valid and unique per step.
        final ids = <String>{};
        for (final s in steps) {
          expect(ids.add(s['id'] as String), isTrue);
          if (s['type'] == 'choose' || s['type'] == 'listen') {
            final options = (s['options'] as List).cast<String>();
            expect(options.toSet().length, options.length);
            expect(s['answer'], isA<int>());
            expect(s['answer'] as int, inInclusiveRange(0, options.length - 1));
            expect((s['explain'] as String?) ?? '', isNotEmpty);
          }
        }
      },
    );
  }

  test('every package carries a named human approval', () {
    for (final f in files) {
      final p = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(p['review_status'], 'approved');
      expect((p['reviewed_by'] as String), isNotEmpty);
      expect(DateTime.tryParse(p['reviewed_at'] as String), isNotNull);
    }
  });
}
