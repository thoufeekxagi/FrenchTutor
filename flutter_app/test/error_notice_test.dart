import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/widgets/error_notice.dart';

void main() {
  testWidgets('microphone permission error offers Settings recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorNotice(
            message:
                'Microphone permission is required to start a voice session.',
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Microphone access is needed to practice speaking. '
        'Enable it in Settings, then come back, the session will pick up '
        'right where you are.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('regular error stays a plain message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ErrorNotice(message: 'Connection lost')),
      ),
    );

    expect(find.text('Connection lost'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
  });
}
