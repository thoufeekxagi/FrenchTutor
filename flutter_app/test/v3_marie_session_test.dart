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

  live('a speaker tap connects her muted, with no hello, and says the line', (
    tester,
  ) async {
    await pumpHost(tester);
    final f = marie.speak(ctx, 'bonjour');
    expect(marie.phase, V3MariePhase.connecting);
    await tester.pump(const Duration(milliseconds: 310));
    expect(await f, isTrue);
    expect(marie.phase, V3MariePhase.live);
    expect(marie.muted, isTrue, reason: 'audio only: the mic stays closed');
    expect(
      V3MarieSession.debugLog,
      containsAllInOrder(['start-audio', 'speak:bonjour']),
    );
    expect(marie.speakingText, 'bonjour');
    await tester.pump(const Duration(seconds: 2));
    expect(marie.speakingText, isNull, reason: 'cleared when she finishes');
    expect(marie.caption, 'bonjour');
  });

  live('a second tap on a warm call is instant and needs no new connection', (
    tester,
  ) async {
    await pumpHost(tester);
    final f = marie.speak(ctx, 'bonjour');
    await tester.pump(const Duration(milliseconds: 400));
    await f;
    await tester.pump(const Duration(seconds: 2));
    V3MarieSession.debugLog.clear();
    expect(await marie.speak(ctx, 'bonsoir'), isTrue);
    expect(V3MarieSession.debugLog, ['speak:bonsoir']);
  });

  live('a tap while she is still connecting is ignored, not doubled', (
    tester,
  ) async {
    await pumpHost(tester);
    final first = marie.speak(ctx, 'bonjour');
    expect(await marie.speak(ctx, 'bonsoir'), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    await first;
    expect(
      V3MarieSession.debugLog.where((e) => e.startsWith('speak:')).toList(),
      ['speak:bonjour'],
    );
  });

  live('empty text is never sent', (tester) async {
    await pumpHost(tester);
    expect(await marie.speak(ctx, '   '), isFalse);
    expect(V3MarieSession.debugLog, isEmpty);
  });

  live('a muted audio-only call may idle three times as long', (tester) async {
    await pumpHost(tester, idle: const Duration(seconds: 5));
    final f = marie.speak(ctx, 'bonjour');
    await tester.pump(const Duration(milliseconds: 400));
    await f;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 10)); // past the 5 s limit
    expect(marie.phase, V3MariePhase.live, reason: 'closed mic costs nothing');
    await tester.pump(const Duration(seconds: 10)); // past 15 s
    expect(marie.phase, V3MariePhase.idle);
  });

  group('call memory for reconnects', () {
    test('no history leaves the screen context alone', () {
      expect(V3LiveMarieSession.withMemory('SCREEN', const []), 'SCREEN');
    });

    test('keeps only the last six lines, labelled, and trims long ones', () {
      final lines = [
        for (var i = 0; i < 9; i++)
          V3MarieLine(fromMarie: i.isEven, text: 'line $i ${'x' * 300}'),
      ];
      final out = V3LiveMarieSession.withMemory('SCREEN', lines);
      expect(out, startsWith('SCREEN'));
      expect(out, contains('CALL MEMORY'));
      expect(out, isNot(contains('line 2 ')));
      expect(out, contains('line 3 '));
      expect(out, contains('line 8 '));
      expect(out, contains('- You: line 8'));
      expect(out, contains('- Learner: line 7'));
      expect(out.length, lessThan(1500));
    });
  });

  live('an unanswered listening line is heard but never shown', (tester) async {
    await pumpHost(tester);
    final f = marie.speak(ctx, 'Je suis née en avril.', reveal: false);
    await tester.pump(const Duration(milliseconds: 310));
    await f;
    await tester.pump(const Duration(seconds: 3));
    expect(marie.caption, isEmpty, reason: 'the pill must not give the answer');
    expect(marie.history, isEmpty, reason: 'nor the conversation sheet');
    expect(marie.speakingText, isNull);
    // The next normal line is shown again.
    await marie.speak(ctx, 'bonjour');
    await tester.pump(const Duration(seconds: 2));
    expect(marie.caption, 'bonjour');
  });
}
