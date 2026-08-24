import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/tutor_persona.dart';
import '../services/tutor_lip_sync_controller.dart';
import 'tutor_avatar_stage.dart';

/// A contained visual pilot for a more natural 2D tutor.
///
/// Unlike the old raster-plus-mouth-overlay experiment, every frame here is
/// a complete illustration of the same tutor. The audio signal only chooses
/// between complete closed, soft-open, and open-vowel images. Blink and
/// breathing are independent, restrained motion layers. This keeps the
/// renderer honest: if the art direction is rejected, it can be replaced
/// without changing the live audio or transcript pipeline.
class TutorStoryboardAvatarStage extends StatefulWidget {
  const TutorStoryboardAvatarStage({
    super.key,
    required this.persona,
    required this.state,
    this.lipSync,
    this.compact = false,
  });

  final TutorPersona persona;
  final TutorAvatarState state;
  final TutorLipSyncController? lipSync;
  final bool compact;

  @override
  State<TutorStoryboardAvatarStage> createState() =>
      _TutorStoryboardAvatarStageState();
}

class _TutorStoryboardAvatarStageState extends State<TutorStoryboardAvatarStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..repeat();

  String _frameId = 'idle';

  @override
  void initState() {
    super.initState();
    _frameId = _frameFor(widget.state, widget.lipSync?.frame);
    widget.lipSync?.addListener(_onLipSyncChanged);
  }

  @override
  void didUpdateWidget(covariant TutorStoryboardAvatarStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lipSync != widget.lipSync) {
      oldWidget.lipSync?.removeListener(_onLipSyncChanged);
      widget.lipSync?.addListener(_onLipSyncChanged);
    }
    final next = _frameFor(widget.state, widget.lipSync?.frame);
    if (next != _frameId) _frameId = next;
  }

  void _onLipSyncChanged() {
    if (!mounted) return;
    final next = _frameFor(widget.state, widget.lipSync?.frame);
    if (next != _frameId) setState(() => _frameId = next);
  }

  String _frameFor(TutorAvatarState state, TutorLipSyncFrame? frame) {
    if (state != TutorAvatarState.speaking) {
      return state == TutorAvatarState.listening ? 'listening' : 'idle';
    }

    final open = frame?.mouthOpen ?? 0;
    if (open >= 0.48) return 'speaking_open';
    if (open >= 0.08) return 'speaking_soft';
    return 'idle';
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.compact ? 214.0 : 286.0;
    final height = widget.compact ? 238.0 : 318.0;

    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final phase = _motion.value * math.pi * 2;
          final isQuiet = _frameId == 'idle' || _frameId == 'listening';
          final blink =
              isQuiet && _motion.value > 0.78 && _motion.value < 0.825;
          final displayedFrame = blink ? 'blink' : _frameId;
          final tilt = widget.state == TutorAvatarState.speaking
              ? math.sin(phase * 1.15) * 0.006
              : math.sin(phase * 0.55) * 0.004;
          final lift = math.sin(phase) * (isQuiet ? 0.7 : 1.0);

          return Semantics(
            label: '${widget.persona.displayName} tutor, $displayedFrame',
            child: Transform.translate(
              offset: Offset(0, lift),
              child: Transform.rotate(
                angle: tilt,
                child: _FrameImage(
                  key: ValueKey('tutor-storyboard-$displayedFrame'),
                  frameId: displayedFrame,
                  compact: widget.compact,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.lipSync?.removeListener(_onLipSyncChanged);
    _motion.dispose();
    super.dispose();
  }
}

class _FrameImage extends StatelessWidget {
  const _FrameImage({super.key, required this.frameId, required this.compact});

  final String frameId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 90),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.992, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: ClipRRect(
        key: ValueKey(frameId),
        borderRadius: BorderRadius.circular(compact ? 22 : 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.09),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/tutor_camille_storyboard/$frameId.png',
            width: compact ? 214 : 286,
            height: compact ? 238 : 318,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            semanticLabel: 'Tutor expression: $frameId',
          ),
        ),
      ),
    );
  }
}
