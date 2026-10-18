import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Captures real, full-resolution screens of the v3 app for the store
/// screenshots. Run with E2E_SHELL and E2E_FAKE_AUDIO (the tutor lines in the
/// Marie shots are scripted; everything else is the real app).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('capture v3 store screenshots', (tester) async {
    final semantics = tester.ensureSemantics();
    final name = ActiveTutor.current.displayName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    await prefs.setString(v3Key('v3_learn_tab'), 'course');
    final all = await V3Course.load(idPrefixes: const ['s0', 'a1']);
    await prefs.setStringList(
      v3Key('v3_completed_lessons'),
      all.where((l) => l.id.startsWith('s0')).map((l) => l.id).toList(),
    );
    await prefs.remove(v3Key('v3_lesson_position'));
    await prefs.setString(
      'tcf_exam_date',
      DateTime.now().add(const Duration(days: 69)).toIso8601String(),
    );
    final now = DateTime.now();
    final challengeKey =
        'e2e_daily_${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_a1-clinic-message-sample';
    await prefs.remove('$challengeKey.step');
    await prefs.remove('$challengeKey.completed');

    Future<List<String>> labels() async =>
        (probe.describe(tester)['tappable']! as List)
            .map((e) => (e as Map)['label'] as String)
            .toList();
    Future<void> pause([int ms = 700]) =>
        tester.pump(Duration(milliseconds: ms));
    Future<void> tap(String label, {bool starts = false}) async {
      await probe.waitForLabel(tester, label, startsWith: starts);
      await probe.tapLabel(tester, label, startsWith: starts);
      await pause();
    }

    app.main();
    await probe.waitForLabel(
      tester,
      'Continue lesson',
      startsWith: true,
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));

    // 1. Course tab.
    await probe.capture(tester, 'shot_01_course');

    // 2. A lesson: the first word, then a question.
    await tap('Continue lesson', starts: true);
    await probe.waitForLabel(tester, 'Close lesson');
    await pause(900);
    await probe.capture(tester, 'shot_02_lesson_word');

    // 3. Marie in the lesson (scripted lines).
    await tap('Talk to $name');
    await probe.waitForLabel(tester, 'End call with $name');
    await pause(2500);
    V3FakeMarieSession.current!.debugSay(
      'Bonjour means hello. Say it with me: bohn-ZHOOR. Take your time.',
    );
    await pause(3500);
    await probe.capture(tester, 'shot_03_lesson_marie');
    V3FakeMarieSession.current!.debugLearnerSays('Bonjour');
    await pause(500);
    await tap('$name said', starts: true);
    await pause(600);
    await probe.capture(tester, 'shot_04_marie_conversation');
    await tap('Close');
    await tap('End call with $name');
    await tap('Close lesson');
    await probe.waitForLabel(tester, 'Continue lesson', startsWith: true);

    // 4. Full course path.
    await tap('Open the full course path');
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, 'shot_05_course_path');
    await tap('Course');

    // 5. Practice tab, then the daily challenge.
    await tap('Practice');
    await probe.waitForLabel(tester, 'Start challenge.', startsWith: true);
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await probe.capture(tester, 'shot_06_practice');
    await tap('Start challenge.', starts: true);
    await probe.waitFor(
      tester,
      find.text('What time is the appointment?'),
      timeout: const Duration(seconds: 15),
    );
    await pause(900);
    await probe.capture(tester, 'shot_07_daily_listening');
    await tester.tap(find.byKey(const ValueKey('lesson.option.3')));
    await pause(300);
    await tap('Check');
    await probe.waitFor(tester, find.text('Correct'));
    await pause(800);
    await probe.capture(tester, 'shot_08_daily_correct');
    await tap('Continue');
    await probe.waitFor(
      tester,
      find.text('Read the clinic notice. When is this clinic open?'),
    );
    await pause(900);
    await probe.capture(tester, 'shot_09_daily_reading');
    await tester.tap(find.byKey(const ValueKey('lesson.option.2')));
    await pause(300);
    await tap('Check');
    await probe.waitFor(tester, find.text('Correct'));
    await pause(800);
    await tap('Continue');
    await probe.waitFor(tester, find.text('Je voudrais un rendez-vous.'));
    await pause(900);
    await tap('Continue');
    await probe.waitFor(tester, find.text('Challenge complete'));
    await pause(900);
    await probe.capture(tester, 'shot_10_daily_complete');
    await tap('Done');
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, 'shot_11_practice_after');

    // 6. Streak calendar.
    final streak = (await labels()).firstWhere(
      (l) => l.startsWith('Open streak calendar,'),
    );
    await tap(streak);
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await probe.capture(tester, 'shot_12_streak');
    await tester.pageBack();
    await probe.settle(tester, timeout: const Duration(seconds: 8));

    // 7. Stories.
    await tap('Open Stories. Read or listen.');
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, 'shot_13_stories');
    await tap('Close Stories');
    await probe.settle(tester, timeout: const Duration(seconds: 8));

    // 8. Tests tab, and two TCF practice sets.
    await tap('Tests');
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await tap('A2 practice level');
    await probe.capture(tester, 'shot_14_tests');
    await tap('Listening,', starts: true);
    await probe.waitForLabel(tester, 'Close lesson');
    await pause(800);
    await tap('Continue');
    await pause(1200);
    await probe.capture(tester, 'shot_15_exam_listening');
    await tap('Close lesson');
    await probe.waitForLabel(tester, 'Reading,', startsWith: true);
    await tap('B1 practice level');
    await tap('Reading,', starts: true);
    await probe.waitForLabel(tester, 'Close lesson');
    await pause(800);
    await tap('Continue');
    await pause(1200);
    await probe.capture(tester, 'shot_16_exam_reading');
    await tap('Close lesson');
    await probe.waitForLabel(tester, 'Writing,', startsWith: true);
    await tap('Writing,', starts: true);
    await probe.waitForLabel(tester, 'Close lesson');
    await pause(800);
    await tap('Continue');
    await pause(1200);
    await probe.capture(tester, 'shot_17_exam_writing_model');
    semantics.dispose();
  });
}
