import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/tests/v3_exam_sets.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Plays all 16 TCF practice sets (A1 to B2, four formats) from the Tests tab,
/// answering every question from the set's own key.
/// Run with --dart-define=E2E_SHELL=true.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  String cap(String s) => s[0].toUpperCase() + s.substring(1);

  testWidgets('every TCF practice set plays to completion', (tester) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);

    app.main();
    await probe.waitForLabel(
      tester,
      'Tests',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await probe.tapLabel(tester, 'Tests');
    await tester.pump(const Duration(milliseconds: 700));

    var played = 0;
    for (final level in V3ExamSets.levels) {
      await probe.tapLabel(tester, '${level.toUpperCase()} practice level');
      await tester.pump(const Duration(milliseconds: 400));
      for (final skill in V3ExamSets.skills) {
        final lesson = await V3ExamSets.load(level, skill);
        await probe.waitForLabel(tester, '${cap(skill)},', startsWith: true);
        await probe.tapLabel(tester, '${cap(skill)},', startsWith: true);
        await probe.waitForLabel(tester, 'Close lesson');
        await tester.pump(const Duration(milliseconds: 800));
        if (level == 'a1' || level == 'b2') {
          await probe.capture(tester, '60_${level}_$skill');
        }
        for (final step in lesson.steps) {
          final answer = switch (step) {
            V3ChooseStep s => s.answer,
            V3ListenStep s => s.answer,
            _ => -1,
          };
          if (answer >= 0) {
            final option = find.byKey(ValueKey('lesson.option.$answer'));
            await probe.waitFor(tester, option);
            await tester.ensureVisible(option);
            await tester.pump(const Duration(milliseconds: 200));
            await tester.tap(option);
            await tester.pump(const Duration(milliseconds: 200));
            await probe.tapLabel(tester, 'Check');
            await probe.waitFor(tester, find.text('Correct'));
            await tester.pump(const Duration(milliseconds: 700));
          } else {
            await tester.pump(const Duration(milliseconds: 700));
          }
          await probe.waitForLabel(tester, 'Continue');
          await probe.tapLabel(tester, 'Continue');
          await tester.pump(const Duration(milliseconds: 500));
        }
        await probe.waitFor(tester, find.text('Practice complete'));
        await probe.tapLabel(tester, 'Done');
        await probe.waitForLabel(tester, '${cap(skill)},', startsWith: true);
        played++;
      }
    }
    expect(played, 16);
    semantics.dispose();
  });
}
