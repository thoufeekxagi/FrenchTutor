import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../services/mic_mode.dart';

/// The live-call mic-mode control (PILOT_EXECUTION_PLAN.md P1.3): a compact
/// Auto/Hold segmented pill, plus — only when Hold is selected — a wide
/// hold-to-talk button. Deliberately quiet visually: in Auto mode it collapses
/// to just the small pill and stays out of the way.
class MicModeBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isPtt = mode == MicMode.pushToTalk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (isPtt) ...[
            Expanded(child: _holdButton()),
            const SizedBox(width: 10),
          ] else
            const Spacer(),
          _modePill(),
        ],
      ),
    );
  }

  Widget _holdButton() {
    return Semantics(
      button: true,
      enabled: enabled,
      label: isHolding ? 'Release to send' : 'Hold to talk',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (_) {
                HapticFeedback.lightImpact();
                onHoldStart();
              }
            : null,
        onTapUp: enabled
            ? (_) {
                HapticFeedback.lightImpact();
                onHoldEnd();
              }
            : null,
        onTapCancel: enabled ? onHoldEnd : null,
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          height: 52,
          decoration: BoxDecoration(
            color: !enabled
                ? DesignTokens.slate.withValues(alpha: 0.35)
                : isHolding
                ? DesignTokens.success
                : DesignTokens.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isHolding
                    ? CupertinoIcons.waveform
                    : CupertinoIcons.mic_fill,
                color: DesignTokens.surface,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                isHolding ? 'Listening — release when done' : 'Hold to talk',
                style: DesignTokens.body(
                  14,
                  weight: FontWeight.w700,
                ).copyWith(color: DesignTokens.surface),
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
            selected: mode == MicMode.auto,
            onTap: () => onModeChanged(MicMode.auto),
          ),
          _segment(
            label: 'Hold',
            icon: CupertinoIcons.hand_raised_fill,
            selected: mode == MicMode.pushToTalk,
            onTap: () => onModeChanged(MicMode.pushToTalk),
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
        onTap: enabled && !selected ? onTap : null,
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
