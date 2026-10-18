import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Free allowance then the App Store subscription screen. Premium is OFF here.
/// Run with --dart-define=E2E_SHELL=true.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List<String>> labels(WidgetTester t) async =>
      (probe.describe(t)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();

  Future<void> closePaywall(WidgetTester t) async {
    await probe.capture(t, 'paywall_${DateTime.now().millisecondsSinceEpoch}');
    expect(find.byKey(const ValueKey('paywall.purchase.primary')), findsOneWidget);
    await t.pageBack();
    await probe.settle(t, timeout: const Duration(seconds: 8));
  }

  testWidgets('after the free allowance every gate opens the paywall', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', false);
    final course = await V3Course.load(idPrefixes: const ['s0', 'a1']);
    final s0 = course.where((l) => l.id.startsWith('s0')).map((l) => l.id);
    final a1 = course.where((l) => l.id.startsWith('a1')).toList();
    expect(a1.length, greaterThan(8), reason: 'need more than 7 A1 lessons');
    await prefs.setStringList(v3Key('v3_completed_lessons'), [
      ...s0,
      ...a1.take(7).map((l) => l.id),
    ]);
    await prefs.remove(v3Key('v3_lesson_position'));
    // Seven daily challenges already used on other days, a free week that
    // started ten days ago.
    await prefs.setStringList(v3Key('v3_free_daily_days'), [
      for (var i = 1; i <= 7; i++) '2026-01-0$i',
    ]);
    final ago = DateTime.now().subtract(const Duration(days: 10));
    await prefs.setString(
      v3Key('v3_free_started_on'),
      '${ago.year}-${ago.month.toString().padLeft(2, '0')}-'
      '${ago.day.toString().padLeft(2, '0')}',
    );

    app.main();
    await probe.waitForLabel(
      tester,
      'Subscribe to keep going',
      startsWith: true,
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await probe.capture(tester, '40_course_locked');

    // 1. The 8th A1 lesson is locked: the hero opens the paywall.
    await probe.tapLabel(tester, 'Subscribe to keep going', startsWith: true);
    await probe.waitFor(
      tester,
      find.byKey(const ValueKey('paywall.purchase.primary')),
      timeout: const Duration(seconds: 15),
    );
    await closePaywall(tester);

    // 2. The daily challenge: 7 days used, today is a new day.
    await probe.tapLabel(tester, 'Practice');
    await tester.pump(const Duration(milliseconds: 500));
    final practice = await labels(tester);
    expect(
      practice.any((l) => l.startsWith('Start challenge.')),
      isTrue,
      reason: 'challenge tile missing: $practice',
    );
    await probe.tapLabel(tester, 'Start challenge.', startsWith: true);
    await probe.waitFor(
      tester,
      find.byKey(const ValueKey('paywall.purchase.primary')),
      timeout: const Duration(seconds: 15),
    );
    await closePaywall(tester);

    // 3. Tests: the free week is over.
    await probe.tapLabel(tester, 'Tests');
    await tester.pump(const Duration(milliseconds: 600));
    await probe.waitFor(tester, find.byKey(const ValueKey('tests.freeNote')));
    expect(
      find.text('Your free week is over. Subscribe to keep practising.'),
      findsOneWidget,
    );
    await probe.capture(tester, '41_tests_locked');
    await probe.tapLabel(tester, 'Listening', startsWith: true);
    await probe.waitFor(
      tester,
      find.byKey(const ValueKey('paywall.purchase.primary')),
      timeout: const Duration(seconds: 15),
    );
    await closePaywall(tester);
    semantics.dispose();
  });
}
