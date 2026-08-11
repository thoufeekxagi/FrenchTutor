import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/inline_call_controller.dart';
import 'adaptive/adaptive.dart';
import 'learning_card.dart';

/// AppBar `actions` for an inline Marie call (mute + phone toggle) — the
/// same two icons `writing_task_screen.dart` has always had, now shared so
/// grammar/story/listening look and behave identically instead of each
/// reinventing the row.
class InlineCallActions extends StatelessWidget {
  const InlineCallActions({super.key, required this.controller});

  final InlineCallController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.active)
          _CallActionButton(
            label: controller.muted ? 'Unmute' : 'Mute',
            onPressed: controller.toggleMute,
            child: Icon(
              controller.muted
                  ? CupertinoIcons.mic_slash_fill
                  : CupertinoIcons.mic_fill,
              color: DesignTokens.mutedDim,
            ),
          ),
        _CallActionButton(
          label: controller.active
              ? 'End call'
              : controller.connecting
              ? 'Connecting…'
              : 'Talk with Marie',
          onPressed: controller.connecting
              ? null
              : () => controller.toggle(context),
          child: controller.connecting
              ? const SizedBox.square(
                  dimension: 20,
                  child: PSProgressIndicator(),
                )
              : Icon(
                  CupertinoIcons.phone_fill,
                  color: controller.active
                      ? DesignTokens.success
                      : DesignTokens.primary,
                ),
        ),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(width: 44, height: 44, child: Center(child: child)),
      ),
    );
  }
}

/// The inline call's status card — "Connecting…", "Marie is speaking…",
/// "Reconnecting…", or her last transcript line. Only meaningful to show
/// while the call is active/connecting/erroring; callers gate visibility
/// themselves (`controller.isLive || controller.error != null`).
class InlineCallStatusCard extends StatelessWidget {
  const InlineCallStatusCard({
    super.key,
    required this.controller,
    this.listeningLabel = 'Listening.',
    this.showLastTutorLine = true,
  });

  final InlineCallController controller;
  final String listeningLabel;
  final bool showLastTutorLine;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.phone_fill,
            size: 18,
            color: controller.error != null
                ? DesignTokens.primary
                : DesignTokens.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.statusText(listeningLabel: listeningLabel),
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.inkSoft),
                ),
                if (showLastTutorLine &&
                    controller.lastTutorLine != null &&
                    controller.error == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    controller.lastTutorLine!,
                    style: DesignTokens.body(
                      12.5,
                    ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
