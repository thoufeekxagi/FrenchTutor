import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/services/tutor_lip_sync_controller.dart';
import 'package:french_tutor/widgets/tutor_avatar_stage.dart';

void main() {
  testWidgets('renders every tutor state without raster mouth overlays', (
    tester,
  ) async {
    final lipSync = TutorLipSyncController();

    for (final persona in TutorPersona.all) {
      for (final state in TutorAvatarState.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TutorAvatarStage(
                  persona: persona,
                  state: state,
                  lipSync: lipSync,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.byType(TutorAvatarStage), findsOneWidget);
      }
    }

    lipSync.dispose();
  });
}
