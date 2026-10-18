import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/widgets/live_tutor_mascot.dart';

void main() {
  testWidgets('Marie mouth redraw follows the outgoing voice envelope', (
    tester,
  ) async {
    final voiceLevel = ValueNotifier<double>(0);
    addTearDown(voiceLevel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: voiceLevel,
              builder: (context, level, _) => LiveTutorMascot(
                size: 204,
                mood: LiveTutorMascotMood.speaking,
                voiceLevel: level,
              ),
            ),
          ),
        ),
      ),
    );

    CustomPainter mouthPainter() => tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('liveTutor.mascotMouth')),
        )
        .painter!;

    final closedMouth = mouthPainter();
    voiceLevel.value = 0.8;
    await tester.pump(const Duration(milliseconds: 16));
    final openMouth = mouthPainter();

    expect(openMouth, isNot(same(closedMouth)));
    expect(openMouth.shouldRepaint(closedMouth), isTrue);
    expect(tester.takeException(), isNull);
  });
}
