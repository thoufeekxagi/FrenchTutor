import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/screens/auth/speak_auth_screen.dart';

void main() {
  testWidgets('provider buttons stay readable in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(darkMode: true),
        home: const SpeakAuthScreen(),
      ),
    );

    final apple = tester.widget<Text>(find.text('Continue with Apple'));
    final google = tester.widget<Text>(find.text('Continue with Google'));

    expect(apple.style?.color, Colors.black);
    expect(google.style?.color, const Color(0xFF202124));
  });

  testWidgets('Apple provider button stays readable in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(darkMode: false),
        home: const SpeakAuthScreen(),
      ),
    );

    final apple = tester.widget<Text>(find.text('Continue with Apple'));
    final google = tester.widget<Text>(find.text('Continue with Google'));

    expect(apple.style?.color, Colors.white);
    expect(google.style?.color, const Color(0xFF202124));
  });
}
