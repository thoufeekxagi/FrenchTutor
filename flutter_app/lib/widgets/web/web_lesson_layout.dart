import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'web_lesson_rail.dart';

class WebLessonLayout extends StatelessWidget {
  const WebLessonLayout({
    super.key,
    required this.title,
    required this.stageLabel,
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.status,
    required this.statusColor,
    required this.duration,
    required this.stepIndex,
    required this.onExit,
    required this.content,
    required this.controls,
    this.trailing,
    this.debugPanel,
    this.overlay,
  });

  final String title;
  final String stageLabel;
  final int currentStep;
  final int totalSteps;
  final double progress;
  final String status;
  final Color statusColor;
  final String duration;
  final int stepIndex;
  final VoidCallback onExit;
  final Widget content;
  final Widget controls;
  final Widget? trailing;
  final Widget? debugPanel;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  title: title,
                  stageLabel: stageLabel,
                  duration: duration,
                  status: status,
                  statusColor: statusColor,
                  onExit: onExit,
                  trailing: trailing,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final hasRoomForRail = constraints.maxWidth >= 1040;
                      final horizontalPadding = hasRoomForRail ? 40.0 : 24.0;
                      final mainContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [content, ?debugPanel, controls],
                      );
                      final progressRail = WebLessonProgressRail(
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                        progress: progress,
                        statusColor: statusColor,
                        stepIndex: stepIndex,
                        compact: !hasRoomForRail,
                      );

                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          24,
                          horizontalPadding,
                          40,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: hasRoomForRail
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: mainContent),
                                      const SizedBox(width: 28),
                                      SizedBox(width: 280, child: progressRail),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      progressRail,
                                      const SizedBox(height: 16),
                                      mainContent,
                                    ],
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.stageLabel,
    required this.duration,
    required this.status,
    required this.statusColor,
    required this.onExit,
    this.trailing,
  });

  final String title;
  final String stageLabel;
  final String duration;
  final String status;
  final Color statusColor;
  final VoidCallback onExit;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        border: Border(bottom: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'End practice',
            onPressed: onExit,
            icon: const Icon(CupertinoIcons.xmark, size: 18),
            color: DesignTokens.mutedDim,
          ),
          const SizedBox(width: 18),
          Container(width: 1, height: 28, color: DesignTokens.hairline),
          const SizedBox(width: 18),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stageLabel.toUpperCase(),
                style: DesignTokens.mono(
                  10,
                  weight: FontWeight.w700,
                ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
              ),
              const SizedBox(height: 3),
              Text(title, style: DesignTokens.display(18)),
            ],
          ),
          const Spacer(),
          _StatusChip(status: status, color: statusColor),
          const SizedBox(width: 16),
          Text(
            duration,
            style: DesignTokens.mono(12).copyWith(color: DesignTokens.mutedDim),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: DesignTokens.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: DesignTokens.body(
              12,
              weight: FontWeight.w600,
            ).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
