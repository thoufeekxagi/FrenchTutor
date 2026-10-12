import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Boot smoke test. It proves the build, install, launch, screenshot and
/// report loop works, and records exactly what the first screen contains.
/// Payments are bypassed through the debug-only DevSubscriptionOverride key.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('app boots and the first screen is describable', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);

    app.main();
    await probe.settle(tester, timeout: const Duration(seconds: 45));
    await probe.capture(tester, '01_first_screen');

    final seen = probe.describe(tester);
    expect(
      (seen['texts']! as List).isNotEmpty ||
          (seen['semantics']! as List).isNotEmpty,
      isTrue,
      reason: 'First screen rendered no text or semantics: ${seen.toString()}',
    );
    semantics.dispose();
  });
}
