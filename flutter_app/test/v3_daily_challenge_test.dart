import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/daily_challenge/v3_daily_challenge.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';

void main() {
  late Map<String, dynamic> package;

  setUpAll(() async {
    package =
        (jsonDecode(
                  await File(
                    'assets/content/tcf/daily_challenges/a1_clinic_message.json',
                  ).readAsString(),
                )
                as Map)
            .cast<String, dynamic>();
  });

  test('clinic package parses through the existing V3 lesson renderer', () {
    final challenge = V3DailyChallenge.fromJson(package, remote: false);

    expect(challenge.title, 'A clinic message');
    expect(challenge.level, 'a1');
    expect(challenge.primarySkill, 'Listening');
    expect(challenge.lesson.steps, hasLength(3));
    expect(challenge.lesson.steps[0], isA<V3ListenStep>());
    expect(challenge.lesson.steps[1], isA<V3ChooseStep>());
    expect(challenge.lesson.steps[2], isA<V3PhraseStep>());
    expect(challenge.lesson.questionCount, 2);
  });

  test('remote assignment restores its server-owned attempt position', () {
    final remote = <String, dynamic>{
      ...package,
      'attempt': {
        'id': 'd8db699e-66c3-48bf-8b31-111111111111',
        'status': 'started',
        'current_step': 1,
      },
    };
    final challenge = V3DailyChallenge.fromJson(remote, remote: true);

    expect(challenge.remote, isTrue);
    expect(challenge.currentStep, 1);
    expect(challenge.attemptId, 'd8db699e-66c3-48bf-8b31-111111111111');
    expect(challenge.completed, isFalse);
  });

  test('completed remote assignment is not offered again as a new task', () {
    final remote = <String, dynamic>{
      ...package,
      'attempt': {
        'id': 'd8db699e-66c3-48bf-8b31-111111111111',
        'status': 'completed',
        'current_step': 2,
      },
    };
    final challenge = V3DailyChallenge.fromJson(remote, remote: true);

    expect(challenge.completed, isTrue);
    expect(challenge.currentStep, 2);
  });
}
