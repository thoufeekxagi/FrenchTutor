import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'support/probe.dart';

/// Captures each onboarding screen for the store screenshots. Run with
/// --dart-define=ONBOARDING_PREVIEW=true. It stops before the final step, so
/// nothing is saved and no account is touched.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('capture onboarding screens', (tester) async {
    final semantics = tester.ensureSemantics();
    app.main();
    await probe.waitForLabel(
      tester,
      'Continue',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 3));

    Future<List<String>> labels() async =>
        (probe.describe(tester)['tappable']! as List)
            .map((e) => (e as Map)['label'] as String)
            .toList();
    String sig() => (probe.describe(tester)['texts']! as List).join('|');

    for (var i = 1; i <= 14; i++) {
      final l = await labels();
      await probe.capture(tester, 'onb_${i.toString().padLeft(2, '0')}');
      if (l.contains('Start learning') || l.contains('One moment')) break;
      final before = sig();
      if (l.contains('Continue')) {
        await probe.tapLabel(tester, 'Continue');
        await tester.pump(const Duration(milliseconds: 1500));
      }
      if (sig() == before && (await labels()).contains('Skip')) {
        await probe.tapLabel(tester, 'Skip');
        await tester.pump(const Duration(milliseconds: 1500));
      }
      await probe.settle(tester, timeout: const Duration(seconds: 6));
    }
    semantics.dispose();
  });
}
