import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Marie inside a lesson, on a real device, with a scripted Marie (no network,
/// no billing): call button, hello, response pill, conversation sheet, mute,
/// next step, end, silence hang-up, leaving the lesson.
///
/// Run with
///   E2E_DEFINES='--dart-define=E2E_SHELL=true --dart-define=E2E_FAKE_AUDIO=true --dart-define=E2E_MARIE_IDLE_SECONDS=6'
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<void> press(
    WidgetTester tester,
    String label, {
    bool startsWith = false,
  }) async {
    await probe.waitForLabel(tester, label, startsWith: startsWith);
    await probe.tapLabel(tester, label, startsWith: startsWith);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  Future<List<String>> labels(WidgetTester tester) async =>
      (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();

  testWidgets('v3 marie: call, pill, sheet, mute, next step, end, silence', (
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
      'Continue path',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await press(tester, 'Continue path');
    await probe.waitForLabel(tester, 'Talk to $name');
    await probe.capture(tester, '00_lesson_before_call');

    // A speaker tap is the old vocabulary behaviour: Marie says the word on a
    // warm connection, muted, with no hello. The same call then serves chat.
    final first =
        all.firstWhere((l) => l.id == 'a1-u01-words-1').steps.first
            as V3WordStep;
    await press(tester, 'Hear ${first.spoken}');
    await tester.pump(const Duration(seconds: 2));
    expect(V3MarieSession.debugLog, contains('speak:${first.spoken}'));
    expect(await labels(tester), contains('Unmute microphone'));
    await probe.capture(tester, '00b_speaker_tap_warm_call');
    await press(tester, 'End call');
    await probe.waitForLabel(tester, 'Talk to $name');
    V3MarieSession.debugLog.clear();

    // The top button is a phone. Tap: connecting, then live with a hello.
    await probe.tapLabel(tester, 'Talk to $name');
    await tester.pump(const Duration(milliseconds: 150));
    await probe.capture(tester, '01_connecting');
    await probe.waitForLabel(tester, 'End call');
    await probe.waitForLabel(tester, 'End call with $name');
    await tester.pump(const Duration(seconds: 2));
    expect(
      await texts(tester),
      contains(
        'Marie is connected. If you need any assistance, feel free to talk.',
      ),
      reason: 'the first thing she does is say she is connected',
    );
    await probe.capture(tester, '02_live_hello');

    // A long reply: the pill stays at three lines and never covers the lesson.
    const long =
        'Sortie means exit, and you will see it above almost every door in '
        'Canada. Say it slowly: sohR-TEE. Try it now, and notice the last letter '
        'is silent, so the word ends on the TEE sound, not on a T. Take your time.';
    V3FakeMarieSession.current!.debugSay(long);
    await tester.pump(const Duration(seconds: 4));
    await probe.capture(tester, '03_long_reply_pill');
    expect(await labels(tester), contains('Mute microphone'));

    // While she talks the learner can cut her off, and the call stays up.
    V3FakeMarieSession.current!.debugSay(long);
    await tester.pump(const Duration(milliseconds: 300));
    await press(tester, 'Stop $name talking');
    expect(V3MarieSession.debugLog, contains('skip'));
    await probe.capture(tester, '03b_after_skip');
    V3FakeMarieSession.current!.debugSay(long);
    await tester.pump(const Duration(seconds: 4));

    // Tap the pill: the whole conversation.
    await press(tester, '$name said', startsWith: true);
    await probe.capture(tester, '04_conversation_sheet');
    expect(await texts(tester), contains('Conversation'));
    V3FakeMarieSession.current!.debugLearnerSays('Sohr-tee');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      (await texts(tester)).any((t) => t.toString().contains('YOU (AS HEARD)')),
      isTrue,
    );
    await press(tester, 'Close');

    // Mute, then the next step keeps the mute and cuts the old words.
    await press(tester, 'Mute microphone');
    expect(await labels(tester), contains('Unmute microphone'));
    expect(V3MarieSession.debugLog, contains('mute'));
    await probe.capture(tester, '05_muted');
    await press(tester, 'Continue');
    expect(V3MarieSession.debugLog, contains('context:step'));
    expect(
      await labels(tester),
      contains('Unmute microphone'),
      reason: 'a new step must not unmute',
    );
    expect(
      (await texts(tester)).any((t) => t.toString().contains('last letter')),
      isFalse,
      reason: 'her old reply must not follow the learner to the next step',
    );
    await probe.capture(tester, '06_next_step_still_on_call');
    await press(tester, 'Unmute microphone');

    // The same button ends the call. The panel goes away.
    await press(tester, 'End call with $name');
    await probe.waitForLabel(tester, 'Talk to $name');
    expect(await labels(tester), isNot(contains('End call')));
    expect(V3MarieSession.debugLog.last, 'end');
    await probe.capture(tester, '07_call_ended');

    // Call again and say nothing: she hangs up by herself and tells us.
    await press(tester, 'Talk to $name');
    await probe.waitForLabel(tester, 'End call');
    await probe.waitForLabel(
      tester,
      'Talk to $name',
      timeout: const Duration(seconds: 25),
    );
    expect(
      (await texts(
        tester,
      )).any((t) => t.toString().contains('ended after a minute and a half')),
      isTrue,
      reason: 'the silence hang-up must tell the learner why',
    );
    await probe.capture(tester, '08_silence_hangup');

    // Leaving the lesson with a call live hangs up.
    await tester.pump(const Duration(seconds: 5)); // snackbar away
    await press(tester, 'Talk to $name');
    await probe.waitForLabel(tester, 'End call');
    final before = V3MarieSession.debugLog.where((e) => e == 'end').length;
    await press(tester, 'Close lesson');
    await probe.waitForLabel(tester, 'Continue path');
    expect(
      V3MarieSession.debugLog.where((e) => e == 'end').length,
      before + 1,
      reason: 'closing the lesson must hang up',
    );
    semantics.dispose();
  });
}
