import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/widgets/personalized_generation_loader.dart';

void main() {
  testWidgets('shows a useful animated generation state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersonalizedGenerationLoader(content: 'grammar class'),
        ),
      ),
    );

    expect(
      find.text('Your personalized grammar class is rendering'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Reading your learning profile…'), findsOneWidget);
    expect(find.text('Personalizing'), findsNothing);
    expect(find.text('Building'), findsNothing);
    expect(find.text('Polishing'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(
      find.text('Choosing the right situation and dialogue for you…'),
      findsOneWidget,
    );
  });
}
