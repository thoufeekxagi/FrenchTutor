import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Plays the dev sample lesson end to end on a real device. Run with
/// E2E_DEFINES='--dart-define=E2E_SHELL=true'.
///
/// Speaker buttons are asserted to exist but never tapped: tapping one would
/// open a real Gemini Live request and cost money. Their behaviour is covered
/// separately.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List<String>> labels(WidgetTester tester) async =>
      (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();

  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  Future<void> press(WidgetTester tester, String label) async {
    await probe.waitForLabel(tester, label);
    await probe.tapLabel(tester, label);
    // Let the step transition finish before reading the next screen.
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('v3 lesson: sample lesson from Learn to completion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    // Mark every real lesson done so the dev sample is the next one offered,
    // however many real lessons exist.
    final real = (await V3Course.load()).where((l) => !l.dev).map((l) => l.id);
    await prefs.setStringList('v3_completed_lessons', real.toList());

    app.main();

    // Learn offers the sample lesson first.
    await probe.waitForLabel(
      tester,
      'Start lesson',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));
    await probe.capture(tester, '01_learn_hero');
    expect(await texts(tester), contains('Sample lesson: Bonjour'));
    await press(tester, 'Start lesson');

    // Explain step.
    await probe.waitForLabel(tester, 'Continue');
    await probe.capture(tester, '02_explain');
    expect(await texts(tester), contains('Silent letters'));
    var l = await labels(tester);
    expect(l, containsAll(['Hear petit', 'Ask Marie', 'Close lesson']));
    await press(tester, 'Continue');

    // Word steps.
    await probe.capture(tester, '03_word');
    expect(await texts(tester), contains('bonjour'));
    expect(await labels(tester), contains('Hear bonjour'));
    await press(tester, 'Continue');
    expect(await texts(tester), contains('merci'));
    await press(tester, 'Continue');

    // Phrase step.
    await probe.capture(tester, '04_phrase');
    expect(await texts(tester), contains("Je m'appelle Sam."));
    await press(tester, 'Continue');

    // Multiple choice: Check is unavailable until an option is chosen.
    await probe.capture(tester, '05_choose');
    l = await labels(tester);
    expect(l, isNot(contains('Check')), reason: 'Check must start disabled');
    await press(tester, 'hello'); // wrong on purpose
    await probe.waitForLabel(tester, 'Check');
    await press(tester, 'Check');
    await probe.capture(tester, '06_wrong_feedback');
    var t = await texts(tester);
    expect(t, contains('Not quite'));
    expect(t, contains('Answer: thank you'));
    expect(t, contains('Merci means thank you.'));
    await press(tester, 'Continue');

    // Listening step, answered correctly.
    await probe.capture(tester, '07_listen');
    expect(await labels(tester), contains('Play audio'));
    expect(await texts(tester), contains('What time is it?'));
    await press(tester, '8:00');
    await press(tester, 'Check');
    await probe.capture(tester, '08_correct_feedback');
    t = await texts(tester);
    expect(t, contains('Correct'));
    expect(t, contains('Il est huit heures.'));
    await press(tester, 'Continue');

    // Result: one of two questions right, the missed word is listed.
    await probe.capture(tester, '09_complete');
    t = await texts(tester);
    expect(t, contains('Well done.'));
    expect(t, contains('1  of 2 correct'));
    expect(t, contains('merci'));
    final progress = await SharedPreferences.getInstance();
    expect(
      progress.getStringList('v3_completed_lessons'),
      contains('dev-sample'),
      reason: 'completion was not recorded',
    );
    await press(tester, 'Done');

    // Back on Learn, the finished lesson is no longer the next one.
    await probe.waitForLabel(tester, 'Learn');
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, '10_learn_after');
    expect(
      await texts(tester),
      isNot(contains('Sample lesson: Bonjour')),
      reason: 'completed lesson is still offered as next',
    );
    semantics.dispose();
  });
}
