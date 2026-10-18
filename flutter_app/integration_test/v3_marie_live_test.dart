import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// REAL Gemini 3.8 tutor call on the phone (billable, debug builds only).
/// Needs --dart-define=E2E_GEMINI_API_KEY=... and no E2E_FAKE_AUDIO.
/// tool/live_marie_host.py plays Mac-side clips (voices, noise, interruptions)
/// into the phone when this test prints `CMD:<clip>` marks.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);
  final clock = Stopwatch()..start();
  void mark(String m) => print(
    'E2E_MARK ${clock.elapsedMilliseconds} '
    '${DateTime.now().millisecondsSinceEpoch} $m',
  );

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

  String phase(List<String> t) => t.contains('Marie is speaking')
      ? 'SPEAKING'
      : t.contains('Listening')
      ? 'LISTENING'
      : t.contains('Marie is thinking')
      ? 'THINKING'
      : 'OTHER';

  Future<void> pumpFor(WidgetTester t, int ms) async {
    for (var i = 0; i < ms ~/ 200; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  /// Plays [clip] on the Mac and watches the call. Returns whether Marie
  /// started speaking, and waits for her to finish when she did.
  Future<bool> turn(
    WidgetTester t,
    String label,
    String clip, {
    required bool expectReply,
    int replyWaitS = 25,
    int quietWaitS = 10,
    String? interruptClip,
    int interruptAfterMs = 1500,
  }) async {
    var last = '';
    var calm = 0;
    for (var i = 0; i < 100 && calm < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
      calm = phase(await texts(t)) == 'LISTENING' ? calm + 1 : 0;
    }
    mark('STEP $label');
    mark('CMD:$clip');
    var speaking = false;
    var interrupted = false;
    var speakingSince = 0;
    final waitMs = (expectReply ? replyWaitS : quietWaitS) * 1000;
    var elapsed = 0;
    var finishedAfter = -1;
    while (elapsed < waitMs + 6000) {
      await t.pump(const Duration(milliseconds: 200));
      elapsed += 200;
      final p = phase(await texts(t));
      if (p != last) {
        last = p;
        mark('PHASE $p');
      }
      if (p == 'SPEAKING' && !speaking) {
        speaking = true;
        speakingSince = elapsed;
        if (!expectReply) break;
      }
      if (speaking &&
          interruptClip != null &&
          !interrupted &&
          elapsed - speakingSince >= interruptAfterMs) {
        interrupted = true;
        mark('INTERRUPT_NOW');
        mark('CMD:$interruptClip');
      }
      if (speaking && p == 'LISTENING' && elapsed - speakingSince > 1500) {
        if (interruptClip != null && !interrupted) continue;
        finishedAfter = elapsed;
        break;
      }
      if (!speaking && elapsed >= waitMs) break;
    }
    mark('RESULT $label speaking=$speaking finishedAfterMs=$finishedAfter');
    await pumpFor(t, 1500);
    return speaking;
  }

  Future<String> dump(WidgetTester t, String name, String shot) async {
    await press(t, '$name said', startsWith: true);
    await probe.capture(t, shot);
    await press(t, 'Close');
    return shot;
  }

  testWidgets('real marie: voices, noise, fillers, barge-in', (tester) async {
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

    mark('MIC_STATUS_BEFORE ${await Permission.microphone.status}');
    if (!await Permission.microphone.isGranted) {
      mark('MIC_REQUEST_NOW_TAP_ALLOW');
      mark('MIC_STATUS_AFTER ${await Permission.microphone.request()}');
    }
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
    await pumpFor(tester, 9000);

    final results = <String, bool>{};
    results['q_en replies'] = await turn(
      tester,
      '1 clean English question',
      'q_en',
      expectReply: true,
    );
    results['filler silent'] = !await turn(
      tester,
      '2 filler "hmm uh okay"',
      'filler',
      expectReply: false,
    );
    results['hum silent'] = !await turn(
      tester,
      '3 fan hum only',
      'hum',
      expectReply: false,
    );
    mark('BGSTART:babble_bg');
    await pumpFor(tester, 2000);
    results['slower over babble replies'] = await turn(
      tester,
      '4 "say it slower" over background chatter',
      'slower_babble',
      expectReply: true,
    );
    mark('BGSTOP');
    await pumpFor(tester, 1500);
    results['barge-in reply'] = await turn(
      tester,
      '5 barge-in: long request interrupted by "Stop, just goodnight"',
      'long_req',
      expectReply: true,
      replyWaitS: 30,
      interruptClip: 'barge',
    );
    results['french question replies'] = await turn(
      tester,
      '6 French-Canadian voice asks in French',
      'fr_q',
      expectReply: true,
    );
    results['thanks silent'] = !await turn(
      tester,
      '7 "Okay, thanks Marie"',
      'thanks',
      expectReply: false,
    );
    results['recall replies'] = await turn(
      tester,
      '8 context recall by voice',
      'recall',
      expectReply: true,
    );
    await dump(tester, name, '20_final_conversation');
    results.forEach((k, v) => mark('VERDICT $k = ${v ? 'PASS' : 'FAIL'}'));
    await press(tester, 'End call with $name');
    await probe.waitForLabel(tester, 'Talk to $name');
    mark('CALL_ENDED');
    expect(results.values.every((v) => v), isTrue, reason: '$results');
    semantics.dispose();
  });
}
