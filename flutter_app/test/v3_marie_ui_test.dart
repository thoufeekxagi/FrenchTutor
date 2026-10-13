import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/marie/v3_marie_dock.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

/// The call button, the Marie panel, the response pill and the conversation
/// sheet must lay out without overflow on a small phone, a normal phone and an
/// iPad in both directions, at normal and very large text, with long text.
void main() {
  const longReply =
      'Sortie means exit, and you will see it above almost every door in Canada. '
      'Say it slowly: sohR-TEE. Try it now, and notice the last letter is silent, '
      'so the word ends on the TEE sound, not on a T.';
  const sizes = {
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'iPad portrait': Size(810, 1080),
    'iPad landscape': Size(1080, 810),
  };

  for (final entry in sizes.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${entry.key} at ${scale}x text', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        V3MarieSession.debugLog.clear();
        final marie = V3FakeMarieSession();
        addTearDown(marie.dispose);

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: entry.value,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Builder(
                  builder: (c) {
                    ctx = c;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: V3MarieCallButton(
                            session: marie,
                            onTap: () => marie.toggle(c),
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                        V3MarieDock(session: marie),
                        const SizedBox(height: 90),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('marie.dock')), findsNothing);

        // Connecting.
        final f = marie.toggle(ctx);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('marie.dock')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'connecting');
        await tester.pump(const Duration(milliseconds: 600));
        await f;

        // Live, long reply streaming then settled.
        marie.debugSay(longReply);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'streaming');
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull, reason: 'settled');

        // The pill never shows more than three lines.
        final pillText = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const ValueKey('marie.pill')),
                matching: find.byType(Text),
              )
              .first,
        );
        expect(pillText.maxLines, 3);
        expect(pillText.overflow, TextOverflow.ellipsis);

        // The panel leaves room for the lesson.
        final dockHeight = tester
            .getSize(find.byKey(const ValueKey('marie.dock')))
            .height;
        expect(
          dockHeight,
          lessThan(entry.value.height * 0.45),
          reason: 'panel took $dockHeight of ${entry.value.height}',
        );

        // Mute and End are tappable-size.
        for (final k in ['marie.mute', 'marie.end']) {
          final size = tester.getSize(find.byKey(ValueKey(k)));
          expect(size.shortestSide, greaterThanOrEqualTo(44), reason: k);
        }

        // Muted state.
        await tester.tap(find.byKey(const ValueKey('marie.mute')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(marie.muted, isTrue);
        expect(tester.takeException(), isNull, reason: 'muted');

        // Tap the pill: the whole conversation opens, with her full words.
        marie.debugLearnerSays('Sohr-tee');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('marie.pill')));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('marie.sheet')), findsOneWidget);
        final sheet = find.byKey(const ValueKey('marie.sheet'));
        expect(
          find.descendant(
            of: sheet,
            matching: find.textContaining('last letter is silent'),
          ),
          findsWidgets,
          reason: 'the sheet shows her whole reply, not three lines',
        );
        expect(
          find.descendant(
            of: sheet,
            matching: find.textContaining('YOU (AS HEARD)'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'sheet');
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        // End from the panel.
        await tester.tap(find.byKey(const ValueKey('marie.end')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(marie.phase, V3MariePhase.idle);
        expect(find.byKey(const ValueKey('marie.dock')), findsNothing);
      });
    }
  }
}
