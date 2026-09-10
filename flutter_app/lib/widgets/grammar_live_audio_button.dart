import 'dart:async';

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/inline_call_controller.dart';

/// Plays a Grammar phrase through the already-connected Marie Live socket.
/// Grammar deliberately has no PCM/TTS fallback: the control either queues an
/// exact app command on Live or remains disabled until the call is available.
class GrammarLiveAudioButton extends StatelessWidget {
  const GrammarLiveAudioButton({
    super.key,
    required this.controller,
    required this.text,
    this.size = 40,
    this.iconSize = 20,
  });

  final InlineCallController? controller;
  final String text;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: IconButton(
      onPressed: controller == null ? null : () => unawaited(_speak(context)),
      tooltip: 'Hear ${text.trim()}',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.volume_up_rounded, size: iconSize),
      color: DesignTokens.primary,
    ),
  );

  Future<void> _speak(BuildContext context) async {
    final call = controller;
    if (call == null || text.trim().isEmpty || !context.mounted) return;
    try {
      if (!call.active) {
        await call.start(context, sendOpeningPrompt: false);
      }
      if (!context.mounted || !call.active) return;
      call.promptTutor('''
APP COMMAND: Pronounce only this exact French text once. Speak clearly at a
learner-friendly pace. Do not translate, explain, or add any other words, then
wait.
EXACT TEXT: "$text"
''');
    } catch (error) {
      debugPrint('Grammar Live pronunciation failed: $error');
    }
  }
}
