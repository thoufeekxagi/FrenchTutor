import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../design/tokens.dart';
import '../services/mic_mode.dart';

/// The live-call mic-mode control (PILOT_EXECUTION_PLAN.md P1.3).
///
/// Auto mode: just the compact Auto/Hold pill, out of the way.
/// Hold mode: a circular hold-to-talk button sized like the other call
/// controls (End/Mute), with a "Hold to speak" caption and — while held — a
/// sweeping arc ring around the button as live "you are being recorded"
/// feedback, so there's never a moment of is-this-working doubt.
class MicModeBar extends StatefulWidget {
  const MicModeBar({
    super.key,
    required this.mode,
    required this.isHolding,
    required this.enabled,
    required this.onModeChanged,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final MicMode mode;
  final bool isHolding;
  final bool enabled;
  final ValueChanged<MicMode> onModeChanged;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<MicModeBar> createState() => _MicModeBarState();
}

class _MicModeBarState extends State<MicModeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isHolding) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant MicModeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHolding && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isHolding && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Row(children: [const Spacer(), _modePill()]),
          Offstage(
            offstage: true,
            child: _primaryButton(widget.mode == MicMode.pushToTalk),
          ),
        ],
      ),
    );
  }

  /// Circular hold-to-talk button, sized to sit as a sibling of the End/Mute
  /// circles. The sweeping arc ring only exists while held — live recording
  /// feedback, not decoration.
  Widget _primaryButton(bool isPtt) {
    const buttonSize = 58.0;
    const ringSize = 74.0;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: isPtt
          ? (widget.isHolding ? 'Release to send' : 'Hold to talk')
          : 'Microphone',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: null,
        onTapDown: isPtt && widget.enabled
            ? (_) {
                HapticFeedback.lightImpact();
                widget.onHoldStart();
              }
            : null,
        onTapUp: isPtt && widget.enabled
            ? (_) {
                HapticFeedback.lightImpact();
                widget.onHoldEnd();
              }
            : null,
        onTapCancel: isPtt && widget.enabled ? widget.onHoldEnd : null,
        child: SizedBox(
          width: ringSize,
          height: ringSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isPtt && widget.isHolding)
                AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) => CustomPaint(
                    size: const Size(ringSize, ringSize),
                    painter: _RecordingRingPainter(
                      progress: _spin.value,
                      color: DesignTokens.success,
                    ),
                  ),
                ),
              AnimatedScale(
                duration: DesignTokens.durationFast,
                scale: widget.isHolding ? 1.05 : 1.0,
                child: AnimatedContainer(
                  duration: DesignTokens.durationFast,
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    color: !widget.enabled
                        ? DesignTokens.slate.withValues(alpha: 0.35)
                        : widget.isHolding
                        ? DesignTokens.success
                        : isPtt
                        ? DesignTokens.primary
                        : DesignTokens.ink,
                    shape: BoxShape.circle,
                    boxShadow: widget.isHolding
                        ? [
                            BoxShadow(
                              color: DesignTokens.success.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    widget.isHolding
                        ? CupertinoIcons.waveform
                        : CupertinoIcons.mic_fill,
                    color: DesignTokens.surface,
                    size: 23,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePill() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DesignTokens.slate.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            label: 'Auto',
            icon: CupertinoIcons.waveform_path,
            selected: widget.mode == MicMode.auto,
            onTap: () => widget.onModeChanged(MicMode.auto),
          ),
          _segment(
            label: 'Hold',
            icon: CupertinoIcons.hand_raised_fill,
            selected: widget.mode == MicMode.pushToTalk,
            onTap: () => widget.onModeChanged(MicMode.pushToTalk),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label microphone mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled && !selected ? onTap : null,
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? DesignTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: DesignTokens.ink.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? DesignTokens.primary : DesignTokens.slateDim,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: DesignTokens.body(12, weight: FontWeight.w600).copyWith(
                  color: selected ? DesignTokens.ink : DesignTokens.slateDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sweeping arc that orbits the hold button while recording — the same
/// "live" cue voice apps use, drawn in-palette.
class MicPrimaryButton extends StatelessWidget {
  const MicPrimaryButton({
    super.key,
    required this.mode,
    required this.isHolding,
    required this.isMuted,
    required this.enabled,
    required this.onAutoTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final MicMode mode;
  final bool isHolding;
  final bool isMuted;
  final bool enabled;
  final VoidCallback onAutoTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final isPtt = mode == MicMode.pushToTalk;
    final label = isPtt
        ? (isHolding ? 'Release to send' : 'Hold to speak')
        : (isMuted ? 'Unmute' : 'Mute');
    final color = !enabled
        ? DesignTokens.slate.withValues(alpha: 0.35)
        : isPtt
        ? (isHolding ? DesignTokens.success : DesignTokens.primary)
        : (isMuted ? DesignTokens.slate : DesignTokens.ink);
    final icon = isPtt
        ? (isHolding ? CupertinoIcons.waveform : CupertinoIcons.mic_fill)
        : (isMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: !isPtt && enabled ? onAutoTap : null,
        onTapDown: isPtt && enabled
            ? (_) {
                HapticFeedback.lightImpact();
                onHoldStart();
              }
            : null,
        onTapUp: isPtt && enabled
            ? (_) {
                HapticFeedback.lightImpact();
                onHoldEnd();
              }
            : null,
        onTapCancel: isPtt && enabled ? onHoldEnd : null,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: DesignTokens.durationFast,
                width: 58,
                height: 58,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: DesignTokens.surface, size: 23),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: DesignTokens.body(11.5, weight: FontWeight.w600)
                    .copyWith(
                      color: isHolding
                          ? DesignTokens.success
                          : DesignTokens.slateDim,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingRingPainter extends CustomPainter {
  const _RecordingRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final start = progress * 2 * math.pi;
    // Main sweeping arc.
    canvas.drawArc(
      rect.deflate(2),
      start,
      math.pi * 1.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // Faint full track behind it.
    canvas.drawArc(
      rect.deflate(2),
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _RecordingRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
