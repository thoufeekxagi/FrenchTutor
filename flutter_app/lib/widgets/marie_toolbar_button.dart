import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/api_keys.dart';
import '../services/lesson_speech_service.dart';
import '../screens/session/session_screen.dart';

/// A phone-icon toolbar button that reaches Marie from anywhere in a lab — not just at the
/// end of a session. Deactivates any local speech service before pushing the live call
/// (single-owner audio-session rule). Ported from MarieAccess.swift's `MarieToolbarButton`.
class MarieToolbarButton extends StatelessWidget {
  const MarieToolbarButton({super.key, this.lessonContext, this.stage});

  final String? lessonContext;
  final String? stage;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        LessonSpeechService.shared.deactivate();
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => SessionScreen(
              apiKey: ApiKeys.geminiKey,
              lessonContext: lessonContext,
              stage: stage,
            ),
          ),
        );
      },
      icon: const Icon(Icons.phone, color: Passeport.maroon),
    );
  }
}
