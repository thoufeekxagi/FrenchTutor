import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Plays EVERY authored lesson on a real device, answering each question from
/// the lesson file's own answer key. It proves each lesson loads, every step
/// renders, every key is reachable, and each lesson finishes with a perfect
/// score and is recorded. Run with E2E_DEFINES='--dart-define=E2E_SHELL=true'.
///
/// Speakers are never tapped (that calls Gemini Live and costs money).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  Future<void> press(WidgetTester tester, String label) async {
    await probe.waitForLabel(tester, label);
    await probe.tapLabel(tester, label);
    await tester.pump(const Duration(milliseconds: 650));
  }

  testWidgets('v3 course walk: every lesson, every step', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    await prefs.remove('v3_completed_lessons');

    app.main();
    final lessons = await V3Course.load();
    expect(lessons.length, greaterThanOrEqualTo(3));
    await probe.waitForLabel(
      tester,
      'Start lesson',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));

    for (final lesson in lessons) {
      // Learn offers this lesson next.
      await probe.waitForLabel(tester, 'Start lesson');
      await probe.settle(
        tester,
        timeout: const Duration(seconds: 8),
        quiet: const Duration(milliseconds: 1200),
      );
      expect(
        await texts(tester),
        contains(lesson.title),
        reason: 'Learn did not offer "${lesson.title}" next',
      );
      await press(tester, 'Start lesson');

      for (final step in lesson.steps) {
        final tag = '${lesson.id}_${step.id}';
        switch (step) {
          case V3ChooseStep s:
            await probe.waitForLabel(tester, s.options[s.answer]);
            await probe.capture(tester, '${tag}_question');
            await press(tester, s.options[s.answer]);
            await press(tester, 'Check');
            expect(
              await texts(tester),
              contains('Correct'),
              reason: '$tag: the keyed answer was not accepted',
            );
          case V3ListenStep s:
            await probe.waitForLabel(tester, s.options[s.answer]);
            await probe.capture(tester, '${tag}_question');
            await press(tester, s.options[s.answer]);
            await press(tester, 'Check');
            expect(
              await texts(tester),
              contains('Correct'),
              reason: '$tag: the keyed answer was not accepted',
            );
          default:
            await probe.waitForLabel(tester, 'Continue');
            await probe.capture(tester, tag);
        }
        await press(tester, 'Continue');
      }

      // Finished: perfect score, then back to Learn.
      final q = lesson.questionCount;
      final t = await texts(tester);
      expect(t, contains('Well done.'), reason: '${lesson.id} did not finish');
      if (q > 0) {
        expect(t, contains('$q  of $q correct'));
      }
      await press(tester, 'Done');
      final done = (await SharedPreferences.getInstance()).getStringList(
        'v3_completed_lessons',
      );
      expect(done, contains(lesson.id), reason: '${lesson.id} not recorded');
    }
    semantics.dispose();
  });
}
