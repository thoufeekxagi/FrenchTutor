import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Captures the exam screens (premium on) so their look can be reviewed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('exam screens', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    app.main();
    await probe.waitForLabel(tester, 'Tests', timeout: const Duration(seconds: 60));
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await probe.tapLabel(tester, 'Tests');
    await tester.pump(const Duration(milliseconds: 700));
    await probe.capture(tester, '50_tests_tab');
    await probe.tapLabel(tester, 'Listening', startsWith: true);
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await probe.capture(tester, '51_exam_readiness');
    await tester.pageBack();
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await probe.tapLabel(tester, 'Marie');
    await tester.pump(const Duration(milliseconds: 700));
    await probe.tapLabel(tester, 'TCF speaking practice');
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await probe.capture(tester, '52_speaking_mocks');
    semantics.dispose();
  });
}
