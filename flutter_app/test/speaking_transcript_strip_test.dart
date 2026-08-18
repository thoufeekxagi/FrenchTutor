import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/chat_message.dart';
import 'package:french_tutor/widgets/speaking_transcript_strip.dart';

void main() {
  testWidgets('transcript uses two-sided bubbles without a You label', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpeakingTranscriptStrip(
            messages: [
              ChatMessage(role: 'tutor', content: 'Bonjour'),
              ChatMessage(role: 'user', content: 'Bonjour'),
            ],
            controller: controller,
            tutorName: 'Mathieu',
            height: 220,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('You'), findsNothing);
    expect(find.text('Conversation'), findsNothing);
    expect(find.text('Listening'), findsNothing);
    expect(find.text('Bonjour'), findsNWidgets(2));
    final bubbles = find.byType(SelectableText).evaluate().toList();
    expect(bubbles, hasLength(2));
    final tutorBubble = tester.getRect(find.byWidget(bubbles[0].widget));
    final userBubble = tester.getRect(find.byWidget(bubbles[1].widget));
    final rail = tester.getRect(find.byType(SpeakingTranscriptStrip));
    expect(userBubble.left, greaterThan(tutorBubble.left));
    expect(userBubble.right, greaterThan(rail.center.dx));
    // The viewport stays fixed so new turns cannot move the tutor stage. The
    // ListView inside the rail owns scrolling instead.
    expect(tester.getSize(find.byType(SpeakingTranscriptStrip)).height, 228);
  });

  testWidgets('long turns stay inside the clipped transcript rail', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpeakingTranscriptStrip(
            messages: [
              ChatMessage(
                role: 'tutor',
                content:
                    'Bonjour, comment allez-vous aujourd’hui ? Répétez doucement cette phrase.',
              ),
              ChatMessage(
                role: 'user',
                content:
                    'Bonjour. Je vais bien et je voudrais pratiquer une phrase un peu plus longue avec vous.',
              ),
              ChatMessage(
                role: 'tutor',
                content: 'Très bien, essayons encore.',
              ),
              ChatMessage(role: 'user', content: 'Bonjour.'),
            ],
            controller: controller,
            tutorName: 'Julien',
            height: 148,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = tester.getRect(find.byType(SpeakingTranscriptStrip));
    for (final text in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      expect(text.maxLines, isNull);
    }
    for (final selectable in find.byType(SelectableText).evaluate()) {
      final rect = tester.getRect(find.byWidget(selectable.widget));
      expect(rect.left, greaterThanOrEqualTo(rail.left));
      expect(rect.right, lessThanOrEqualTo(rail.right));
    }
    // The widget reserves an 8px bottom breathing-room margin outside the
    // clipped rail itself; the bounded rail remains at the requested height.
    expect(rail.height, lessThanOrEqualTo(156));
  });
}
