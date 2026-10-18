import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// V3 shell walk on a real device. Run with
/// E2E_DEFINES='--dart-define=E2E_SHELL=true'. The debug-only E2E_SHELL
/// switch skips sign-in so the shell can be reached without an account.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List<String>> labels(WidgetTester tester) async =>
      (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();

  testWidgets('v3 shell: four tabs, Learn today and path, dark toggle', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    for (final key in [
      'v3_completed_lessons',
      'v3_lesson_position',
      'v3_last_active_lesson',
      'v3_last_completed_lesson',
    ]) {
      await prefs.remove(v3Key(key));
    }
    await prefs.setString(
      'tcf_exam_date',
      DateTime.now().add(const Duration(days: 64)).toIso8601String(),
    );

    app.main();
    await probe.waitForLabel(
      tester,
      'Learn',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 20));
    await probe.capture(tester, '01_learn_today');

    // All four tabs exist, nothing else is in the bar.
    final l = await labels(tester);
    for (final tab in ['Learn', 'Marie', 'Tests', 'Me']) {
      expect(l, contains(tab), reason: 'missing tab $tab in $l');
    }
    expect(l, isNot(contains('Photo tutor')));
    // The exam countdown lives on the Practice tab.
    await probe.tapLabel(tester, 'Practice');
    await tester.pump(const Duration(milliseconds: 500));
    final texts = probe.describe(tester)['texts']! as List;
    await probe.tapLabel(tester, 'Course');
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      texts.any((t) => t.toString().contains('days')),
      isTrue,
      reason: 'exam countdown missing: $texts',
    );
    expect(texts, contains('Learn'));

    // Path tab shows units.
    await probe.tapLabel(tester, 'Open the full course path');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.capture(tester, '02_learn_path');
    // Stage 0 is open first (it holds the next lesson) and lists its lessons.
    var pathLabels = await labels(tester);
    expect(
      pathLabels.any((t) => t.startsWith('Stage 0, ')),
      isTrue,
      reason: 'Stage 0 card missing: $pathLabels',
    );
    expect(
      pathLabels.where((t) => t.startsWith('Lesson, ')).length,
      greaterThanOrEqualTo(5),
      reason: 'Stage 0 lessons missing: $pathLabels',
    );
    // Collapse it: every unit card is then on screen.
    await probe.tapLabel(tester, 'Stage 0, Sounds and spelling');
    await tester.pump(const Duration(milliseconds: 600));
    pathLabels = await labels(tester);
    for (var n = 1; n <= 5; n++) {
      expect(
        pathLabels.any((t) => t.startsWith('Unit $n, ')),
        isTrue,
        reason: 'Unit $n missing on Path: $pathLabels',
      );
    }
    // Opening Unit 1 shows its lessons.
    await probe.tapLabel(tester, 'Unit 1, Introduce yourself');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.capture(tester, '02b_learn_path_unit1');
    pathLabels = await labels(tester);
    expect(
      pathLabels.any((t) => t.startsWith('Lesson, Words:')),
      isTrue,
      reason: 'Unit 1 lessons missing: $pathLabels',
    );

    // Marie tab.
    await probe.tapLabel(tester, 'Marie');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.capture(tester, '03_marie');
    final marieTexts = probe.describe(tester)['texts']! as List;
    expect(marieTexts, contains('TCF CANADA PRACTICE'));
    expect(marieTexts, contains('Practise French with Marie'));
    expect(marieTexts, isNot(contains('Ask anything.')));
    expect(await labels(tester), contains('TCF speaking practice'));

    // Tests tab: real TCF format numbers.
    await probe.tapLabel(tester, 'Tests');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.capture(tester, '04_tests');
    expect(
      (await labels(
        tester,
      )).any((t) => t.startsWith('Listening, 39 questions')),
      isTrue,
    );

    // Me tab and the dark toggle.
    await probe.tapLabel(tester, 'Me');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.capture(tester, '05_me_light');
    final meTexts = probe.describe(tester)['texts']! as List;
    expect(meTexts, contains('TCF Canada'));
    expect(meTexts, isNot(contains('NCLC 7')));
    final lightPrint = probe.fingerprint(tester);

    // Settings and the purchase surface use the same TCF-focused V3 system.
    await probe.tapLabel(tester, 'Settings');
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await probe.capture(tester, '05b_settings');
    var settingsTexts = probe.describe(tester)['texts']! as List;
    expect(settingsTexts, contains('TCF Canada'));
    expect(settingsTexts, contains('Study reminder'));
    expect(settingsTexts, isNot(contains('Everyday French')));
    expect(settingsTexts, isNot(contains('TEF Canada')));

    await probe.waitForLabel(tester, 'Study reminder', startsWith: true);
    expect(
      await probe.tapLabel(tester, 'Study reminder', startsWith: true),
      isTrue,
      reason: 'study reminder row is not accessible',
    );
    await probe.waitFor(tester, find.text('Remind me to practise'));
    await probe.settle(tester, timeout: const Duration(seconds: 5));
    await probe.capture(tester, '05c_reminder_editor');
    settingsTexts = probe.describe(tester)['texts']! as List;
    expect(settingsTexts, contains('Remind me to practise'));
    expect(settingsTexts, contains('Save'));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Study reminders'), findsNothing);
    await probe.settle(tester, timeout: const Duration(seconds: 5));

    await probe.waitForLabel(tester, 'Membership', startsWith: true);
    expect(
      await probe.tapLabel(tester, 'Membership', startsWith: true),
      isTrue,
      reason: 'membership row is not accessible',
    );
    await probe.waitFor(
      tester,
      find.text('One goal: TCF Canada.'),
      timeout: const Duration(seconds: 30),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 20));
    await probe.capture(tester, '05d_tcf_paywall');
    settingsTexts = probe.describe(tester)['texts']! as List;
    expect(settingsTexts, contains('One goal: TCF Canada.'));
    expect(
      settingsTexts,
      containsAll(['Listening', 'Speaking with Marie', 'Reading', 'Writing']),
    );
    expect(await labels(tester), contains('Restore purchase'));
    await tester.tap(find.byKey(const ValueKey('paywall.back')));
    await probe.waitFor(tester, find.text('Study reminder'));
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await tester.tap(find.byKey(const ValueKey('settings.back')));
    await probe.waitForLabel(tester, 'Me');
    await probe.settle(tester, timeout: const Duration(seconds: 8));

    await probe.tapLabel(tester, 'Dark mode');
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.waitForLabel(tester, 'Me');
    await probe.tapLabel(tester, 'Me');
    await tester.pump(const Duration(milliseconds: 800));
    await probe.capture(tester, '06_me_dark');
    expect(
      prefs.getBool('app_dark_mode') ?? false,
      isTrue,
      reason: 'dark mode was not persisted',
    );
    expect(lightPrint, isNotEmpty);

    // Back to Learn in dark to check it renders.
    await probe.tapLabel(tester, 'Learn');
    await tester.pump(const Duration(milliseconds: 800));
    await probe.capture(tester, '07_learn_dark');

    // Leave the device in light mode.
    await probe.tapLabel(tester, 'Me');
    await probe.tapLabel(tester, 'Dark mode');
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    semantics.dispose();
  });
}
