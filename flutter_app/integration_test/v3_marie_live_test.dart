import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// REAL Gemini 3.8 tutor call on the phone (billable, debug builds only).
/// Needs --dart-define=E2E_GEMINI_API_KEY=... and no E2E_FAKE_AUDIO.
/// A host script (tool/live_marie_host.sh) watches the log for E2E_SAY markers
/// and speaks into the phone from the Mac.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);
  final clock = Stopwatch()..start();
  void mark(String m) => print('E2E_MARK ${clock.elapsedMilliseconds} $m');

  Future<List<String>> texts(WidgetTester t) async =>
      (probe.describe(t)['texts']! as List).map((e) => e.toString()).toList();

  Future<void> press(
    WidgetTester t,
    String label, {
    bool startsWith = false,
  }) async {
    await probe.waitForLabel(t, label, startsWith: startsWith);
    await probe.tapLabel(t, label, startsWith: startsWith);
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> waitSecs(WidgetTester t, int s) async {
    for (var i = 0; i < s * 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<List<String>> transcript(
    WidgetTester t,
    String name,
    String shot,
  ) async {
    await press(t, '$name said', startsWith: true);
    final all = await texts(t);
    await probe.capture(t, shot);
    await press(t, 'Close');
    mark('TRANSCRIPT[$shot] ${all.join(' | ')}');
    return all;
  }

  testWidgets('real marie: greeting, quiet echo check, question, interrupt', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final name = ActiveTutor.current.displayName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    final all = await V3Course.load();
    await prefs.setStringList(
      v3Key('v3_completed_lessons'),
      all.where((l) => l.id != 'a1-u01-words-1').map((l) => l.id).toList(),
    );
    await prefs.remove(v3Key('v3_lesson_position'));
    V3MarieSession.debugLog.clear();

    app.main();
    await probe.waitForLabel(
      tester,
      'Continue lesson',
      startsWith: true,
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await press(tester, 'Continue lesson', startsWith: true);
    await probe.waitForLabel(tester, 'Talk to $name');

    mark('CALL_START');
    await probe.tapLabel(tester, 'Talk to $name');
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      final l = (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();
      if (l.contains('End call')) break;
      if (l.contains('Not now') && l.contains('Continue')) {
        await probe.tapLabel(tester, 'Continue');
      }
    }
    await probe.waitForLabel(
      tester,
      'End call',
      timeout: const Duration(seconds: 20),
    );
    mark('CALL_LIVE');
    await waitSecs(tester, 14);
    await probe.capture(tester, '10_after_greeting');
    final greet = await transcript(tester, name, '11_greeting_sheet');
    expect(
      greet.any((t) => t.contains('YOU (AS HEARD)')),
      isFalse,
      reason: 'tutor greeting echo must not become a learner turn',
    );

    // Quiet phase: the phone plays nothing, the room is silent.
    mark('QUIET_START');
    await waitSecs(tester, 20);
    final quiet = await transcript(tester, name, '12_quiet_sheet');
    expect(
      quiet.any((t) => t.contains('YOU (AS HEARD)')),
      isFalse,
      reason: 'silence must not produce a learner turn',
    );

    // Mac speaks a French question at the phone.
    mark('SAY_Q1');
    await waitSecs(tester, 22);
    final q1 = await transcript(tester, name, '13_q1_sheet');
    expect(
      q1.any((t) => t.contains('YOU (AS HEARD)')),
      isTrue,
      reason: 'the learner question must be heard',
    );

    // Ask for a long answer, then interrupt while she talks.
    mark('SAY_Q2_LONG');
    await waitSecs(tester, 5);
    mark('SAY_INTERRUPT');
    await waitSecs(tester, 18);
    await transcript(tester, name, '14_interrupt_sheet');

    await press(tester, 'End call with $name');
    await probe.waitForLabel(tester, 'Talk to $name');
    mark('CALL_ENDED');
    semantics.dispose();
  });
}
