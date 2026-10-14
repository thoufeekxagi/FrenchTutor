import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
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

  /// Long reading passages push the answers below the screen. A learner
  /// scrolls to them; the walker does the same until the option is on screen.
  Future<void> scrollToLabel(WidgetTester tester, String label) async {
    final screenHeight = tester.view.physicalSize.height;
    for (var i = 0; i < 8; i++) {
      final hits = (probe.describe(tester)['tappable']! as List)
          .cast<Map>()
          .where((e) => e['label'] == label)
          .toList();
      if (hits.isNotEmpty) {
        final rect = hits.first['rect'] as Map;
        final bottom = (rect['y'] as num) + (rect['h'] as num);
        if (bottom < screenHeight * 0.80) return;
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('v3 course walk: every lesson, every step', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    // E2E_ONLY=s0-01,a1-u02 limits the walk to lessons whose id starts with
    // one of the prefixes. Everything else is marked done, so the Learn hero
    // walks the chosen lessons in order. No filter walks every lesson.
    const only = String.fromEnvironment('E2E_ONLY');
    final all = await V3Course.load();
    final prefixes = only.isEmpty ? <String>[] : only.split(',');
    final lessons = prefixes.isEmpty
        ? all
        : all.where((l) => prefixes.any(l.id.startsWith)).toList();
    expect(lessons, isNotEmpty);
    await prefs.setStringList(
      v3Key('v3_completed_lessons'),
      all.where((l) => !lessons.contains(l)).map((l) => l.id).toList(),
    );
    await prefs.remove(v3Key('v3_lesson_position'));

    app.main();
    await probe.waitForLabel(
      tester,
      'Continue path',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));

    for (final lesson in lessons) {
      // Learn offers this lesson next.
      await probe.waitForLabel(tester, 'Continue path');
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
      await press(tester, 'Continue path');

      for (final step in lesson.steps) {
        final tag = '${lesson.id}_${step.id}';
        switch (step) {
          case V3ChooseStep s:
            await probe.waitForLabel(tester, s.options[s.answer]);
            if (step == lesson.steps.first) {
              await probe.capture(tester, '${tag}_question');
            }
            await scrollToLabel(tester, s.options[s.answer]);
            await press(tester, s.options[s.answer]);
            await press(tester, 'Check');
            expect(
              await texts(tester),
              contains('Correct'),
              reason: '$tag: the keyed answer was not accepted',
            );
          case V3ListenStep s:
            await probe.waitForLabel(tester, s.options[s.answer]);
            if (step == lesson.steps.first) {
              await probe.capture(tester, '${tag}_question');
            }
            await scrollToLabel(tester, s.options[s.answer]);
            await press(tester, s.options[s.answer]);
            await press(tester, 'Check');
            expect(
              await texts(tester),
              contains('Correct'),
              reason: '$tag: the keyed answer was not accepted',
            );
          default:
            await probe.waitForLabel(tester, 'Continue');
            if (step == lesson.steps.first || step == lesson.steps.last) {
              await probe.capture(tester, tag);
            }
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
        v3Key('v3_completed_lessons'),
      );
      expect(done, contains(lesson.id), reason: '${lesson.id} not recorded');
    }
    semantics.dispose();
  });
}
