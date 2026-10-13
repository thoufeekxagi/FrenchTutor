import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

void main() {
  late V3FakeMarieSession marie;
  late BuildContext ctx;

  /// Every test ends the call so no timer outlives it.
  void live(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await marie.end();
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  Future<void> pumpHost(WidgetTester tester, {Duration? idle}) async {
    V3MarieSession.debugLog.clear();
    marie = V3FakeMarieSession(idleLimit: idle ?? const Duration(seconds: 90));
    addTearDown(marie.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  Future<void> connect(WidgetTester tester) async {
    final f = marie.toggle(ctx);
    await tester.pump(const Duration(milliseconds: 600));
    await f;
  }

  live('one tap connects, the same tap ends', (tester) async {
    await pumpHost(tester);
    expect(marie.phase, V3MariePhase.idle);
    final f = marie.toggle(ctx);
    expect(marie.phase, V3MariePhase.connecting);
    await tester.pump(const Duration(milliseconds: 600));
    await f;
    expect(marie.phase, V3MariePhase.live);
    await marie.toggle(ctx);
    expect(marie.phase, V3MariePhase.idle);
    expect(V3MarieSession.debugLog, ['start', 'end']);
  });

  live('she says hello first, so the learner knows she is there', (
    tester,
  ) async {
    await pumpHost(tester);
    await connect(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(marie.caption, contains('connected'));
    expect(marie.history.first.fromMarie, isTrue);
  });

  live('her words stream into the caption, then settle in history', (
    tester,
  ) async {
    await pumpHost(tester);
    await connect(tester);
    await tester.pump(const Duration(seconds: 2));
    marie.debugSay('Sortie means exit. Say it with me.');
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.marieSpeaking, isTrue);
    expect(marie.caption, isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(marie.marieSpeaking, isFalse);
    expect(marie.caption, 'Sortie means exit. Say it with me.');
  });

  live('history keeps only the latest lines', (tester) async {
    await pumpHost(tester);
    await connect(tester);
    for (var i = 0; i < 20; i++) {
      marie.debugLearnerSays('line $i');
    }
    expect(marie.history.length, V3MarieSession.maxHistory);
    expect(marie.history.last.text, 'line 19');
    expect(marie.history.last.fromMarie, isFalse);
  });

  live('mute only works while live and stays until toggled', (tester) async {
    await pumpHost(tester);
    await marie.toggleMute();
    expect(marie.muted, isFalse, reason: 'nothing to mute before the call');
    await connect(tester);
    await marie.toggleMute();
    expect(marie.muted, isTrue);
    marie.screenChanged();
    expect(marie.muted, isTrue, reason: 'a new step must not unmute');
    await marie.toggleMute();
    expect(marie.muted, isFalse);
  });

  live('moving to the next step cuts the old words, call stays up', (
    tester,
  ) async {
    await pumpHost(tester);
    await connect(tester);
    marie.debugSay('A very long explanation that should be cut off now');
    await tester.pump(const Duration(milliseconds: 150));
    expect(marie.caption, isNotEmpty);
    marie.screenChanged();
    expect(marie.caption, isEmpty);
    expect(marie.phase, V3MariePhase.live);
    await tester.pump(const Duration(seconds: 3));
    expect(marie.caption, isEmpty, reason: 'old reply must not come back');
    expect(V3MarieSession.debugLog, contains('context:step'));
  });

  live('answering a question refreshes context without a new step', (
    tester,
  ) async {
    await pumpHost(tester);
    await connect(tester);
    marie.screenUpdated();
    expect(V3MarieSession.debugLog, contains('context:update'));
  });

  live('screen changes before the call do nothing', (tester) async {
    await pumpHost(tester);
    marie.screenChanged();
    marie.screenUpdated();
    expect(V3MarieSession.debugLog, isEmpty);
  });

  live('silence hangs up and leaves a note to show once', (tester) async {
    await pumpHost(tester, idle: const Duration(seconds: 5));
    await connect(tester);
    await tester.pump(const Duration(seconds: 2)); // greeting finishes
    expect(marie.phase, V3MariePhase.live);
    await tester.pump(const Duration(seconds: 6));
    expect(marie.phase, V3MariePhase.idle);
    expect(marie.endedNote, isNotNull);
    marie.clearEndedNote();
    expect(marie.endedNote, isNull);
  });

  live('talking keeps the call alive past the idle limit', (tester) async {
    await pumpHost(tester, idle: const Duration(seconds: 5));
    await connect(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
      marie.debugLearnerSays('Bonjour $i');
    }
    expect(marie.phase, V3MariePhase.live);
  });

  live('only a real background ends the call, not Split View', (tester) async {
    await pumpHost(tester);
    await connect(tester);
    marie.handleLifecycle(AppLifecycleState.inactive);
    expect(
      marie.phase,
      V3MariePhase.live,
      reason: 'inactive is Split View or Control Center',
    );
    marie.handleLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(marie.phase, V3MariePhase.idle);
  });

  live('a second tap while connecting ends it cleanly', (tester) async {
    await pumpHost(tester);
    final f = marie.toggle(ctx);
    expect(marie.phase, V3MariePhase.connecting);
    await marie.toggle(ctx);
    expect(marie.phase, V3MariePhase.idle);
    await tester.pump(const Duration(seconds: 1));
    await f;
    expect(
      marie.phase,
      V3MariePhase.idle,
      reason: 'late connect must not revive',
    );
  });

  live('skip cuts what she is saying and keeps the call', (tester) async {
    await pumpHost(tester);
    await connect(tester);
    await tester.pump(const Duration(seconds: 2));
    marie.debugSay('A long answer that the learner does not want to wait for');
    await tester.pump(const Duration(milliseconds: 200));
    expect(marie.marieSpeaking, isTrue);
    await marie.skip();
    expect(marie.caption, isEmpty);
    expect(marie.marieSpeaking, isFalse);
    expect(marie.phase, V3MariePhase.live);
    await tester.pump(const Duration(seconds: 3));
    expect(
      marie.caption,
      isEmpty,
      reason: 'the rest of the reply must not return',
    );
  });

  live('skip with no call does nothing', (tester) async {
    await pumpHost(tester);
    await marie.skip();
    expect(V3MarieSession.debugLog, isEmpty);
  });
}
