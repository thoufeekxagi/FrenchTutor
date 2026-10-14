import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// V3 onboarding end to end on a real device: greeting, three value screens,
/// optional exam date, level, optional reminders, then the consent gate. The
/// Marie practice (offered after sign-in) is not part of this test, so it never
/// opens a microphone or calls the model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('v3 onboarding: value screens to account gate', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    const dark = bool.fromEnvironment('E2E_DARK');
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', dark);

    app.main();

    // 0 animated greeting (Hello, Bonjour, Salut, Bienvenue), then Continue
    await probe.waitForLabel(
      tester,
      'Continue',
      timeout: const Duration(seconds: 40),
    );
    await probe.capture(tester, '00_greeting');
    expect((probe.describe(tester)['texts']! as List), contains('ParleSprint'));
    await probe.tapLabel(tester, 'Continue');

    // 1 one clear course: the four levels
    await probe.waitFor(tester, find.text('One clear course.'));
    await probe.capture(tester, '01_course');
    final course = probe.describe(tester)['texts']! as List;
    for (final level in ['A1', 'A2', 'B1', 'B2']) {
      expect(course, contains(level));
    }
    await probe.tapLabel(tester, 'Continue');

    // 2 one goal: TCF Canada, four skills
    await probe.waitFor(tester, find.text('One goal:\nTCF Canada.'));
    await probe.capture(tester, '02_goal');
    final goal = probe.describe(tester)['texts']! as List;
    for (final skill in ['Listening', 'Speaking', 'Reading', 'Writing']) {
      expect(goal, contains(skill));
    }
    await probe.tapLabel(tester, 'Continue');

    // 3 Marie in every lesson
    await probe.waitFor(tester, find.text('Practice every lesson with Marie.'));
    await probe.capture(tester, '03_marie_lessons');
    await probe.tapLabel(tester, 'Continue');

    // 4 first name, then the optional exam date
    await probe.waitFor(tester, find.text('What should we call you?'));
    await probe.capture(tester, '04_name');
    await tester.tap(find.byKey(const ValueKey('onboarding.name')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('onboarding.name')),
      'Priya',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await probe.tapLabel(tester, 'Continue');
    await probe.waitFor(tester, find.text('When is your TCF Canada exam?'));
    await probe.capture(tester, '04b_exam_date');
    await probe.tapLabel(tester, 'Skip for now');

    // 5 current level (B1: A1 would start an audio warm-up)
    await probe.waitFor(
      tester,
      find.text('What is your current French level?'),
    );
    await probe.capture(tester, '05_level');
    await probe.tapLabel(tester, 'B1');
    await tester.pump(const Duration(milliseconds: 400));
    await probe.capture(tester, '06_level_b1_selected');
    await probe.tapLabel(tester, 'Continue');

    // 6 optional reminders: skip them
    await probe.waitFor(tester, find.text('Set a learning reminder'));
    await probe.capture(tester, '07_reminders');
    final before = probe.fingerprint(tester);
    await probe.tapLabel(tester, 'Skip for now');

    // 7 the pledge: personal, never a promise of a score
    await probe.waitFor(tester, find.text('Dear Priya,'));
    await probe.capture(tester, '08_pledge');
    expect(
      probe.describe(tester)['texts']! as List,
      contains(
        'ParleSprint is proud to help you get ready for the TCF Canada exam.',
      ),
    );
    await probe.tapLabel(tester, 'Start learning');

    // 8 onboarding is over: the AI consent gate comes next, never an account
    // wall up front. The test stops here and does not agree on anyone's behalf.
    await probe.waitFor(
      tester,
      find.text('Agree and continue'),
      timeout: const Duration(seconds: 30),
    );
    await probe.capture(tester, '09_consent_gate');
    expect(
      probe.fingerprint(tester),
      isNot(before),
      reason: 'Finishing onboarding must leave the onboarding screen',
    );
    semantics.dispose();
  });
}
