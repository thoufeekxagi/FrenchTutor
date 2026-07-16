import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../config/api_keys.dart';
import '../design/app_router.dart';
import '../design/tokens.dart';
import '../screens/session/session_screen.dart';
import '../services/lesson_speech_service.dart';

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
      tooltip: 'Talk with Marie',
      constraints: const BoxConstraints(
        minWidth: DesignTokens.minTapTarget,
        minHeight: DesignTokens.minTapTarget,
      ),
      onPressed: () {
        LessonSpeechService.shared.deactivate();
        Navigator.of(context).push(
          AppRouter.route(
            fullscreenDialog: true,
            builder: (_) => SessionScreen(
              apiKey: ApiKeys.geminiKey,
              lessonContext: lessonContext,
              stage: stage,
            ),
          ),
        );
      },
      icon: const Icon(CupertinoIcons.phone_fill, color: DesignTokens.primary),
    );
  }
}
