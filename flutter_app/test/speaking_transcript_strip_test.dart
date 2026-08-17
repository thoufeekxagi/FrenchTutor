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
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Align && widget.alignment == Alignment.centerLeft,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Align && widget.alignment == Alignment.centerRight,
      ),
      findsOneWidget,
    );
    // A short exchange should size to its content instead of reserving the
    // full transcript viewport for an empty answer area.
    expect(
      tester.getSize(find.byType(SpeakingTranscriptStrip)).height,
      lessThan(220),
    );
  });
}
