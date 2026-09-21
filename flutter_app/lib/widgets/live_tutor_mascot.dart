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
    this.voiceLevel = 0,
  });

  final double size;
  final bool isSpeaking;
  final LiveTutorMascotMood mood;

  /// Smoothed-ish instantaneous level of the tutor's outgoing PCM audio.
  /// The parent supplies this from the actual Gemini audio stream; it is not
  /// a timer or a transcript pulse.
  final double voiceLevel;

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
  bool _mouthOpen = false;
  double _smoothedVoiceLevel = 0;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant LiveTutorMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final speaking = widget.effectiveMood == LiveTutorMascotMood.speaking;
    if (!speaking) {
      _smoothedVoiceLevel = 0;
      _mouthOpen = false;
      return;
    }

    // A short envelope smooths packet-to-packet PCM variation. Hysteresis
    // keeps the mouth from chattering at the speech/noise boundary.
    _smoothedVoiceLevel += (widget.voiceLevel - _smoothedVoiceLevel) * 0.38;
    if (!_mouthOpen && _smoothedVoiceLevel >= 0.12) _mouthOpen = true;
    if (_mouthOpen && _smoothedVoiceLevel <= 0.055) _mouthOpen = false;
  }

  @override
  void dispose() {
    _motion.dispose();
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
        animation: _motion,
        builder: (context, _) {
          final phase = _motion.value * math.pi * 2;
          final isScolding = mood == LiveTutorMascotMood.scolding;
          final isSpeaking = mood == LiveTutorMascotMood.speaking;
          // Swap the existing closed/open mascot drawings only when the
          // outgoing tutor audio envelope crosses a real speech threshold.
          final mouthOpen = isSpeaking && _mouthOpen;
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
              ? 1 +
                    math.max(0, math.sin(phase * 1.4 + 0.3)) * 0.009 +
                    _smoothedVoiceLevel * 0.008
              : 1.0;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 90),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Transform.translate(
              key: ValueKey(asset),
              offset: Offset(pushBack, -bob),
              child: Transform.rotate(
                angle: tilt,
                child: Transform.scale(
                  scale: scale,
                  child: SvgPicture.asset(
                    asset,
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
