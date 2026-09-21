import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LiveTutorMascotMood { listening, speaking, scolding }

/// The Live tutor mascot uses the same blue character identity as the product
/// reference. Its motion is deliberately client-side so it stays responsive
/// to Gemini Live audio and connection state without asking the model to render
/// animation frames.
class LiveTutorMascot extends StatefulWidget {
  const LiveTutorMascot({
    super.key,
    this.size = 190,
    this.isSpeaking = false,
    this.mood = LiveTutorMascotMood.listening,
    this.speechPulse = 0,
  });

  final double size;
  final bool isSpeaking;
  final LiveTutorMascotMood mood;

  /// Incremented as output transcription arrives. It gives the mascot a
  /// speech-shaped mouth pulse without tying animation to a brittle timer.
  final int speechPulse;

  LiveTutorMascotMood get effectiveMood =>
      isSpeaking && mood == LiveTutorMascotMood.listening
      ? LiveTutorMascotMood.speaking
      : mood;

  @override
  State<LiveTutorMascot> createState() => _LiveTutorMascotState();
}

class _LiveTutorMascotState extends State<LiveTutorMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late final AnimationController _mouthPulse;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _mouthPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(covariant LiveTutorMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameSpeaking =
        widget.effectiveMood == LiveTutorMascotMood.speaking &&
        oldWidget.effectiveMood != LiveTutorMascotMood.speaking;
    final receivedSpeech = widget.speechPulse > oldWidget.speechPulse;
    if (becameSpeaking || receivedSpeech) {
      _mouthPulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _mouthPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.effectiveMood;

    return Semantics(
      image: true,
      label: switch (mood) {
        LiveTutorMascotMood.listening => 'Live tutor listening',
        LiveTutorMascotMood.speaking => 'Live tutor speaking',
        LiveTutorMascotMood.scolding => 'Live tutor correcting playfully',
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_motion, _mouthPulse]),
        builder: (context, _) {
          final phase = _motion.value * math.pi * 2;
          final isScolding = mood == LiveTutorMascotMood.scolding;
          final isSpeaking = mood == LiveTutorMascotMood.speaking;
          final mouthOpen = isSpeaking && _mouthPulse.value > 0.12;
          final asset = mood == LiveTutorMascotMood.speaking && mouthOpen
              ? 'assets/images/live_tutor/mascot_speaking_open.svg'
              : mood == LiveTutorMascotMood.scolding
              ? 'assets/images/live_tutor/mascot_scolding.svg'
              : 'assets/images/live_tutor/mascot_listening.svg';
          // Two slow, incommensurate waves keep the body alive without making
          // it look like a bouncing sticker or a rigid loading indicator.
          final variation =
              math.sin(phase * 2.3) * 0.7 + math.cos(phase * 0.8) * 0.35;
          final bob = math.sin(phase) * (isScolding ? 1.4 : 2.0) + variation;
          final pushBack = isScolding
              ? math.sin(phase * 1.8) * 2.0 + variation * 0.35
              : variation * 0.22;
          final tilt = isScolding
              ? math.sin(phase * 1.8) * 0.012
              : math.sin(phase * 0.7) * 0.004;
          final scale = isScolding
              ? 1 + math.max(0, math.sin(phase * 1.8)) * 0.01
              : isSpeaking
              ? 1 + math.max(0, math.sin(phase * 1.4 + 0.3)) * 0.009
              : 1.0;

          return Transform.translate(
            offset: Offset(pushBack, -bob),
            child: Transform.rotate(
              angle: tilt,
              child: Transform.scale(
                scale: scale,
                child: SvgPicture.asset(
                  asset,
                  key: ValueKey(asset),
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
