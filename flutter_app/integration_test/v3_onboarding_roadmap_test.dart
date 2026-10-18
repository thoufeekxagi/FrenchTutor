import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'support/probe.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('course onboarding shows all four roadmap levels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    app.main();

    await probe.waitForLabel(
      tester,
      'Continue',
      timeout: const Duration(seconds: 40),
    );
    await probe.tapLabel(tester, 'Continue');
    await probe.waitFor(tester, find.text('One clear course.'));
    await probe.capture(tester, '01_course_roadmap');

    final visibleText = probe.describe(tester)['texts']! as List;
    for (final level in ['A1', 'A2', 'B1', 'B2']) {
      expect(visibleText, contains(level));
    }

    semantics.dispose();
  });
}
