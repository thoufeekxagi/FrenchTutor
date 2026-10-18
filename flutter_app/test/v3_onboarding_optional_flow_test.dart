import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/design/tokens.dart';
import 'package:french_tutor/v3/onboarding/v3_onboarding_flow.dart';

void main() {
  testWidgets('onboarding continues when optional choices are left blank', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: V3OnboardingFlow(onFinished: () {})),
      ),
    );

    Future<void> continueThrough(String key) async {
      final cta = find.byKey(ValueKey<String>(key));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pump(const Duration(milliseconds: 520));
    }

    await continueThrough('onboarding.helloContinue');
    await continueThrough('onboarding.courseContinue');
    await continueThrough('onboarding.goalContinue');
    await continueThrough('onboarding.practiceContinue');

    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('onboarding.name')),
    );
    expect(nameField.decoration?.filled, isFalse);
    expect(nameField.decoration?.fillColor, Colors.transparent);
    final fieldContainer = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('onboarding.name')),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final fieldDecoration = fieldContainer.decoration! as BoxDecoration;
    expect(
      fieldDecoration.borderRadius,
      BorderRadius.circular(DesignTokens.radiusLarge),
    );

    await continueThrough('onboarding.nameContinue');
    await continueThrough('onboarding.examDateContinue');
    await continueThrough('onboarding.levelContinue');
    await continueThrough('onboarding.remindersSave');

    expect(find.text('Welcome,'), findsOneWidget);
  });
}
