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
    final speaking =
        widget.effectiveMood == LiveTutorMascotMood.speaking ||
        widget.effectiveMood == LiveTutorMascotMood.scolding;
    if (!speaking) {
      _smoothedVoiceLevel = 0;
      return;
    }

    // The parent samples Marie's actual playback PCM. A quick attack and a
    // slightly softer release keep the jaw responsive to syllables without
    // making it chatter on individual samples.
    final level = widget.voiceLevel.clamp(0.0, 1.0);
    final envelope = level > _smoothedVoiceLevel ? 0.78 : 0.64;
    _smoothedVoiceLevel += (level - _smoothedVoiceLevel) * envelope;
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
          final isSpeaking = mood == LiveTutorMascotMood.speaking || isScolding;
          // Let the audio envelope shape the jaw continuously. The old pair
          // of static SVGs made Marie look like she was holding one open-mouth
          // pose for an entire response.
          final energy = ((_smoothedVoiceLevel - 0.045) / 0.43).clamp(0.0, 1.0);
          final mouthOpenness = isSpeaking
              ? math.pow(energy, 0.72).toDouble()
              : 0.0;
          final asset = isScolding
              ? 'assets/images/live_tutor/mascot_scolding.svg'
              : 'assets/images/live_tutor/mascot_listening.svg';
          // Two slow, incommensurate waves keep the body alive without making
          // it look like a bouncing sticker or a rigid loading indicator.
          final variation =
              math.sin(phase * 2.3) * 0.7 + math.cos(phase * 0.8) * 0.35;
          final bob =
              math.sin(phase) *
                  (isScolding
                      ? 1.4
                      : isSpeaking
                      ? 2.8
                      : 2.0) +
              variation +
              mouthOpenness * 1.4;
          final pushBack = isScolding
              ? math.sin(phase * 1.8) * 2.0 + variation * 0.35
              : isSpeaking
              ? math.sin(phase * 1.1) * 1.2 + mouthOpenness * 1.2
              : variation * 0.22;
          final tilt = isScolding
              ? math.sin(phase * 1.8) * 0.012
              : isSpeaking
              ? math.sin(phase * 0.7) * 0.007 + mouthOpenness * 0.003
              : math.sin(phase * 0.7) * 0.004;
          final scale = isScolding
              ? 1 + math.max(0, math.sin(phase * 1.8)) * 0.01
              : isSpeaking
              ? 1 +
                    math.max(0, math.sin(phase * 1.4 + 0.3)) * 0.009 +
                    mouthOpenness * 0.016
              : 1.0;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Transform.translate(
              key: ValueKey(asset),
              offset: Offset(pushBack, -bob),
              child: Transform.rotate(
                angle: tilt,
                child: Transform.scale(
                  scale: scale,
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SvgPicture.asset(asset, fit: BoxFit.contain),
                        if (isSpeaking)
                          IgnorePointer(
                            child: CustomPaint(
                              key: const ValueKey('liveTutor.mascotMouth'),
                              painter: _LiveTutorMouthPainter(mouthOpenness),
                            ),
                          ),
                      ],
                    ),
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

/// Paints a small, audio-reactive mouth over the mascot's existing smile.
/// Geometry follows the SVG's 240×260 viewBox so the overlay stays registered
/// at every widget size without changing the artwork itself.
class _LiveTutorMouthPainter extends CustomPainter {
  const _LiveTutorMouthPainter(this.openness);

  final double openness;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 240, size.height / 260);
    final offsetX = (size.width - 240 * scale) / 2;
    final offsetY = (size.height - 260 * scale) / 2;
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    final patch = Rect.fromCenter(
      center: const Offset(120, 127),
      width: 44,
      height: 38,
    );
    canvas.drawOval(
      patch,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6AB2E6), Color(0xFF65ACE3)],
        ).createShader(patch),
    );

    final amount = openness.clamp(0.0, 1.0);
    if (amount < 0.12) {
      final smile = Path()
        ..moveTo(104, 124)
        ..cubicTo(111, 132, 127, 132, 136, 123);
      canvas.drawPath(
        smile,
        Paint()
          ..color = const Color(
            0xFF192F52,
          ).withValues(alpha: (1 - amount / 0.12).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    if (amount > 0.025) {
      final width = 19 + 17 * amount;
      final height = 3 + 19 * amount;
      final centerY = 127 + amount * 1.5;
      final left = 120 - width / 2;
      final right = 120 + width / 2;
      final top = centerY - height / 2;
      final bottom = centerY + height / 2;
      final mouth = Path()
        ..moveTo(left, centerY - height * 0.18)
        ..cubicTo(
          left + width * 0.05,
          top + height * 0.06,
          120 - width * 0.19,
          top,
          120,
          top + height * 0.12,
        )
        ..cubicTo(
          120 + width * 0.19,
          top,
          right - width * 0.05,
          top + height * 0.06,
          right,
          centerY - height * 0.18,
        )
        ..cubicTo(
          right - width * 0.03,
          bottom - height * 0.04,
          left + width * 0.03,
          bottom - height * 0.04,
          left,
          centerY - height * 0.18,
        )
        ..close();
      canvas.drawPath(mouth, Paint()..color = const Color(0xFF162744));

      if (amount > 0.34) {
        final tongue = Rect.fromCenter(
          center: Offset(120, centerY + height * 0.28),
          width: width * 0.56,
          height: height * 0.24,
        );
        canvas.drawOval(tongue, Paint()..color = const Color(0xFFF07878));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveTutorMouthPainter oldDelegate) =>
      oldDelegate.openness != openness;
}
