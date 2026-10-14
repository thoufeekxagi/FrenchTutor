import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// The approved Today screen on a real device. Run with
/// E2E_DEFINES='--dart-define=E2E_SHELL=true'.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List<String>> labels(WidgetTester tester) async =>
      (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();
  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  testWidgets('v3 home: wordmark, Today, continue card, three tiles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);

    app.main();
    await probe.waitForLabel(
      tester,
      'Continue path',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));
    await probe.capture(tester, '01_home');

    final t = await texts(tester);
    for (final expected in ['TCF CANADA', 'Today', 'CONTINUE PATH']) {
      expect(t, contains(expected), reason: 'missing "$expected" in $t');
    }
    expect(
      t.any((e) => e.toString().contains('NEXT LESSON')),
      isFalse,
      reason: 'the card must say Continue path, not Next lesson',
    );
    final l = await labels(tester);
    for (final tile in [
      'Review flashcards',
      'Read stories',
      'Listen to stories',
    ]) {
      expect(l, contains(tile), reason: 'missing tile "$tile" in $l');
    }
    // Bottom bar: the four tabs.
    for (final tab in ['Learn', 'Marie', 'Tests', 'Me']) {
      expect(l, contains(tab));
    }

    // A new learner has no review yet, and is told why.
    await probe.tapLabel(tester, 'Review flashcards');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.capture(tester, '02_review_empty');
    expect(
      await texts(tester),
      contains('Review opens after your first word lesson.'),
    );

    // Listening tile opens Stories in Listen mode.
    await tester.pump(const Duration(seconds: 4));
    await probe.tapLabel(tester, 'Listen to stories');
    await tester.pump(const Duration(milliseconds: 900));
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, '03_listen_mode');
    expect(
      (await texts(tester)).any((e) => e.toString().startsWith('Listen first')),
      isTrue,
    );

    // Stories tile (back on Today first), then the Path tab.
    await probe.tapLabel(tester, 'Today');
    await tester.pump(const Duration(milliseconds: 500));
    await probe.tapLabel(tester, 'Read stories');
    await tester.pump(const Duration(milliseconds: 900));
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, '04_read_mode');
    expect(
      (await texts(
        tester,
      )).any((e) => e.toString().startsWith('Short stories at your level')),
      isTrue,
    );
    semantics.dispose();
  });
}
