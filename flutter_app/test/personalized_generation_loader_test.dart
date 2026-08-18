import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/widgets/personalized_generation_loader.dart';

void main() {
  testWidgets('shows a concise, left-aligned generation state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersonalizedGenerationLoader(content: 'grammar class'),
        ),
      ),
    );

    expect(find.text('Preparing grammar class'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.text('Using your level and goals to choose the next activity.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.wand_stars), findsNothing);
  });
}
