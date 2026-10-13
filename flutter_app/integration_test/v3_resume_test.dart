import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// A learner leaves a lesson half way and comes back: Learn offers Resume at
/// the right step, the lesson reopens exactly there, and finishing it clears
/// the saved position. Also checks a double tap on Continue never skips a step.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<void> press(WidgetTester tester, String label) async {
    await probe.waitForLabel(tester, label);
    await probe.tapLabel(tester, label);
    await tester.pump(const Duration(milliseconds: 650));
  }

  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  testWidgets('v3 resume: leave half way, come back, same step', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    final all = await V3Course.load();
    final target = all.firstWhere((l) => l.id == 'a1-u01-words-1');
    await prefs.setStringList(
      v3Key('v3_completed_lessons'),
      all.where((l) => l.id != target.id).map((l) => l.id).toList(),
    );
    await prefs.remove(v3Key('v3_lesson_position'));

    app.main();
    await probe.waitForLabel(
      tester,
      'Start lesson',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await press(tester, 'Start lesson');

    // Three steps in. The 4th word must be on screen after resuming.
    for (var i = 0; i < 3; i++) {
      await press(tester, 'Continue');
    }
    final fourth = target.steps[3] as V3WordStep;
    expect(await texts(tester), contains(fourth.fr));

    // A rapid double tap on Continue moves exactly one step.
    await probe.tapLabel(tester, 'Continue');
    await probe.tapLabel(tester, 'Continue');
    await tester.pump(const Duration(milliseconds: 700));
    final fifth = target.steps[4] as V3WordStep;
    final sixth = target.steps[5] as V3WordStep;
    final t = await texts(tester);
    expect(t, contains(fifth.fr), reason: 'double tap should move one step');
    expect(t, isNot(contains(sixth.fr)), reason: 'double tap skipped a step');

    // Leave, and come back.
    await press(tester, 'Close lesson');
    await probe.waitForLabel(tester, 'Resume lesson');
    await probe.settle(tester, timeout: const Duration(seconds: 6));
    await probe.capture(tester, '01_resume_offered');
    expect(
      (await texts(tester)).any((e) => e.toString().startsWith('RESUME')),
      isTrue,
    );
    await press(tester, 'Resume lesson');
    await probe.capture(tester, '02_resumed');
    expect(
      await texts(tester),
      contains(fifth.fr),
      reason: 'resume did not return to the same step',
    );

    // Finish it: position cleared, lesson recorded.
    for (var i = target.steps.indexOf(fifth); i < target.steps.length; i++) {
      final step = target.steps[i];
      if (step is V3ChooseStep) {
        await press(tester, step.options[step.answer]);
        await press(tester, 'Check');
      } else if (step is V3ListenStep) {
        await press(tester, step.options[step.answer]);
        await press(tester, 'Check');
      }
      await press(tester, 'Continue');
    }
    await press(tester, 'Done');
    final prefs2 = await SharedPreferences.getInstance();
    expect(
      prefs2.getStringList(v3Key('v3_completed_lessons')),
      contains(target.id),
    );
    final pos = prefs2.getStringList(v3Key('v3_lesson_position')) ?? const [];
    expect(pos.where((e) => e.startsWith('${target.id}:')), isEmpty);
    semantics.dispose();
  });
}
