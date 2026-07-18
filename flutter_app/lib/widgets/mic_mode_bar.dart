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
    final isPtt = widget.mode == MicMode.pushToTalk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: isPtt ? _holdLayout() : _autoLayout(),
    );
  }

  Widget _autoLayout() {
    return Row(children: [const Spacer(), _modePill()]);
  }

  Widget _holdLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.isHolding ? 'Listening — release when done' : 'Hold to speak',
          style: DesignTokens.body(11.5, weight: FontWeight.w600).copyWith(
            color: widget.isHolding
                ? DesignTokens.success
                : DesignTokens.slateDim,
          ),
        ),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            Row(children: [const Spacer(), _modePill()]),
            _holdButton(),
          ],
        ),
      ],
    );
  }

  /// Circular hold-to-talk button, sized to sit as a sibling of the End/Mute
  /// circles. The sweeping arc ring only exists while held — live recording
  /// feedback, not decoration.
  Widget _holdButton() {
    const buttonSize = 58.0;
    const ringSize = 74.0;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.isHolding ? 'Release to send' : 'Hold to talk',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (_) {
                HapticFeedback.lightImpact();
                widget.onHoldStart();
              }
            : null,
        onTapUp: widget.enabled
            ? (_) {
                HapticFeedback.lightImpact();
                widget.onHoldEnd();
              }
            : null,
        onTapCancel: widget.enabled ? widget.onHoldEnd : null,
        child: SizedBox(
          width: ringSize,
          height: ringSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.isHolding)
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
                        : DesignTokens.primary,
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
