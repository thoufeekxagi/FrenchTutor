import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// V3 onboarding end to end on a real device. Run with
/// E2E_DEFINES='--dart-define=SKIP_NOTIFICATION_PROMPT=true' so the iOS
/// permission alert (which the test driver cannot tap) is skipped.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('v3 onboarding: welcome to account gate', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    const dark = bool.fromEnvironment('E2E_DARK');
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', dark);

    app.main();

    // 0 launch splash (auto advances after 1.7s)
    await probe.waitFor(
      tester,
      find.text('TCF CANADA PREP'),
      timeout: const Duration(seconds: 40),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await probe.capture(tester, '00_launch');

    // 1 welcome
    await probe.waitForLabel(
      tester,
      'Get started',
      timeout: const Duration(seconds: 40),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await probe.capture(tester, '01_welcome');
    expect(probe.describe(tester)['texts'], contains('01'));
    await probe.tapLabel(tester, 'Get started');

    // 2 level
    await probe.waitForLabel(tester, 'Starting from zero', startsWith: true);
    await probe.capture(tester, '02_level');
    await probe.tapLabel(tester, 'I can hold a conversation', startsWith: true);
    await tester.pump(const Duration(milliseconds: 400));
    await probe.capture(tester, '03_level_b1_selected');
    await probe.tapLabel(tester, 'Continue');

    // 3 Marie
    await probe.waitForLabel(tester, 'Start 3-minute check');
    await probe.capture(tester, '04_marie');
    await probe.tapLabel(tester, 'Skip for now');

    // 4 rhythm
    await probe.waitForLabel(tester, '20 minutes');
    await probe.tapLabel(tester, '20 minutes');
    await probe.tapLabel(tester, 'sat');
    await tester.pump(const Duration(milliseconds: 400));
    await probe.capture(tester, '05_rhythm');
    await probe.tapLabel(tester, 'Continue');

    // 5 ready
    await probe.waitForLabel(tester, 'Create my account');
    await probe.capture(tester, '06_ready');
    final ready = probe.describe(tester)['texts']! as List;
    expect(ready, contains('NCLC 7'));
    expect(ready.any((t) => t.toString().contains('20 min')), isTrue);
    expect(ready.any((t) => t.toString().contains('6 days')), isTrue);

    final before = probe.fingerprint(tester);
    await probe.tapLabel(tester, 'Create my account');
    await probe.settle(tester, timeout: const Duration(seconds: 20));
    await probe.capture(tester, '07_after_finish');
    expect(
      probe.fingerprint(tester),
      isNot(before),
      reason: 'Finishing onboarding must leave the onboarding screen',
    );
    semantics.dispose();
  });
}
