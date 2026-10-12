import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Discovery walk. Advances through whatever the app shows, capturing every
/// screen. It never asserts product behavior. Use the output
/// (`artifacts/e2e/probe.json` and `artifacts/e2e/shots/`) to write real tests
/// against facts.
///
/// Each screen: first pick a preferred option if one is offered (once), then
/// tap the first forward label. Labels that spend money, delete data or leave
/// the app are never tapped. A screen that does not change after two forward
/// taps ends the walk and is reported.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  const prefer = [
    'TEF / TCF Canada',
    'Beginner',
    'Complete beginner',
    'Brand new',
  ];
  const forward = [
    'Build my plan',
    'Get started',
    'Continue',
    'Next',
    'Skip',
    'Skip for now',
    'Not now',
    'Maybe later',
    'Done',
    'I agree',
    'Agree and continue',
  ];
  const forbidden = [
    'subscribe',
    'purchase',
    'buy',
    'delete',
    'sign out',
    'log out',
    'restore',
  ];

  testWidgets('explore: advance through the first screens', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);

    app.main();
    await probe.settle(tester, timeout: const Duration(seconds: 45));

    final picked = <String>{};
    var stuck = 0;
    for (var step = 1; step <= 30; step++) {
      final name = 'step_${step.toString().padLeft(2, '0')}';
      await probe.capture(tester, name);
      final before = probe.fingerprint(tester);
      final labels = (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();

      var acted = false;
      for (final option in prefer) {
        final id = '$before#$option';
        if (!picked.contains(id) && labels.any((l) => l.startsWith(option))) {
          picked.add(id);
          acted = await probe.tapLabel(tester, option, startsWith: true);
          break;
        }
      }
      if (!acted) {
        for (final candidate in forward) {
          final unsafe = forbidden.any(
            (f) => candidate.toLowerCase().contains(f),
          );
          if (!unsafe && labels.contains(candidate)) {
            acted = await probe.tapLabel(tester, candidate);
            break;
          }
        }
      }
      if (!acted) break;

      await probe.settle(
        tester,
        timeout: const Duration(seconds: 10),
        quiet: const Duration(milliseconds: 1500),
      );
      if (probe.fingerprint(tester) == before) {
        if (++stuck >= 3) break;
      } else {
        stuck = 0;
      }
    }
    semantics.dispose();
  });
}
