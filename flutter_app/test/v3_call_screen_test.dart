import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/flow/stage_outcome.dart';
import 'package:french_tutor/v3/marie/v3_call_screen.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

void main() {
  testWidgets('the call connects, shows her words, and ends with a result', (
    tester,
  ) async {
    SpeakingResult? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async {
                result = await Navigator.of(context).push<SpeakingResult>(
                  MaterialPageRoute(
                    builder: (_) => V3CallScreen(
                      title: 'Fix my French',
                      subtitle: 'Marie · A2 · Everyday life',
                      stage: 'free_talk',
                      topic: 'test',
                      createSession: () => V3FakeMarieSession(),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Fix my French'), findsOneWidget);
    expect(find.textContaining('Connecting'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('talk.mute')), findsOneWidget);
    expect(find.textContaining('connected'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('talk.end')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Fix my French'), findsNothing);
    expect(result, isNotNull);
    expect(result!.connected, isTrue);
    expect(result!.endedReason, 'user_ended');
  });

  testWidgets('the onboarding call stops itself at the time limit', (
    tester,
  ) async {
    SpeakingResult? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async {
                result = await Navigator.of(context).push<SpeakingResult>(
                  MaterialPageRoute(
                    builder: (_) => V3CallScreen(
                      keyPrefix: 'onboarding.trial',
                      title: 'Practice',
                      subtitle: 'check',
                      stage: 'trial',
                      topic: 'test',
                      limitSeconds: 4,
                      createSession: () => V3FakeMarieSession(),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, isNotNull);
    expect(result!.endedReason, 'completed');
    expect(result!.durationSeconds, greaterThanOrEqualTo(4));
  });
}
