import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/services/tutor_lip_sync_controller.dart';
import 'package:french_tutor/widgets/tutor_avatar_stage.dart';
import 'package:french_tutor/widgets/tutor_storyboard_avatar_stage.dart';

List<int> _pcm({required double amplitude}) {
  final bytes = <int>[];
  for (var sample = 0; sample < 2400; sample++) {
    final value =
        (math.sin(sample * 2 * math.pi * 220 / 24000) * amplitude * 32767)
            .round();
    final unsigned = value < 0 ? value + 0x10000 : value;
    bytes
      ..add(unsigned & 0xff)
      ..add((unsigned >> 8) & 0xff);
  }
  return bytes;
}

void main() {
  testWidgets('pilot switches complete artwork frames from live PCM', (
    tester,
  ) async {
    final lipSync = TutorLipSyncController();
    addTearDown(lipSync.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TutorStoryboardAvatarStage(
            persona: TutorPersona.camille,
            state: TutorAvatarState.speaking,
            lipSync: lipSync,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('tutor-storyboard-idle')), findsOneWidget);

    lipSync.pushPcm16(_pcm(amplitude: 0.05));
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      find.byKey(const ValueKey('tutor-storyboard-speaking_soft')),
      findsOneWidget,
    );

    lipSync.pushPcm16(_pcm(amplitude: 0.24));
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      find.byKey(const ValueKey('tutor-storyboard-speaking_open')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TutorStoryboardAvatarStage(
            persona: TutorPersona.camille,
            state: TutorAvatarState.listening,
            lipSync: lipSync,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      find.byKey(const ValueKey('tutor-storyboard-listening')),
      findsOneWidget,
    );
  });

  testWidgets('pilot keeps the full frame artwork inside the stage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TutorStoryboardAvatarStage(
            persona: TutorPersona.camille,
            state: TutorAvatarState.listening,
            compact: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Image), findsOneWidget);
    expect(find.bySemanticsLabel('Camille tutor, listening'), findsOneWidget);
  });
}
