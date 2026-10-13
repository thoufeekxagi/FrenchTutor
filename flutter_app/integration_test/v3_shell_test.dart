import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
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
    final texts = probe.describe(tester)['texts']! as List;
    expect(
      texts.any((t) => t.toString().contains('days')),
      isTrue,
      reason: 'exam countdown missing: $texts',
    );
    expect(texts, contains('Learn'));

    // Path tab shows units.
    await probe.tapLabel(tester, 'Path');
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
    final lightPrint = probe.fingerprint(tester);
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
