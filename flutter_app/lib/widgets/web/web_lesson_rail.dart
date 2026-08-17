import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/tutor_persona.dart';

const kWebLessonStages = ['Vocabulary', 'Grammar', 'Listening', 'Writing'];

class WebLessonProgressRail extends StatelessWidget {
  const WebLessonProgressRail({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.statusColor,
    required this.stepIndex,
    this.compact = false,
  });

  final int currentStep;
  final int totalSteps;
  final double progress;
  final Color statusColor;
  final int stepIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactProgress(
        currentStep: currentStep,
        totalSteps: totalSteps,
        progress: progress,
        statusColor: statusColor,
        stepIndex: stepIndex,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow('DAILY PATH'),
              const SizedBox(height: 14),
              Text(
                '$currentStep of $totalSteps',
                style: DesignTokens.display(25, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'practice items completed in this stage',
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 7,
                  backgroundColor: DesignTokens.canvasDim,
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow('YOUR ROUTE'),
              const SizedBox(height: 14),
              for (var i = 0; i < kWebLessonStages.length; i++)
                _RouteStep(
                  label: kWebLessonStages[i],
                  isCurrent: i == stepIndex,
                  isDone: i < stepIndex,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RailCard(
          color: DesignTokens.primaryDeep,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                CupertinoIcons.waveform,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ActiveTutor.current.displayName} is with you',
                      style: DesignTokens.body(
                        13,
                        weight: FontWeight.w700,
                      ).copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use your voice, then move on when you are ready.',
                      style: DesignTokens.body(12).copyWith(
                        color: Colors.white.withValues(alpha: 0.68),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _eyebrow(String text) {
    return Text(
      text,
      style: DesignTokens.mono(
        10,
        weight: FontWeight.w700,
      ).copyWith(color: DesignTokens.muted, letterSpacing: 1.1),
    );
  }
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.statusColor,
    required this.stepIndex,
  });

  final int currentStep;
  final int totalSteps;
  final double progress;
  final Color statusColor;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        children: [
          Text(
            '${currentStep.clamp(0, totalSteps)} of $totalSteps',
            style: DesignTokens.body(13, weight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 6,
                backgroundColor: DesignTokens.canvasDim,
                valueColor: AlwaysStoppedAnimation(statusColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            kWebLessonStages[stepIndex.clamp(0, kWebLessonStages.length - 1)],
            style: DesignTokens.body(12).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: color == null ? Border.all(color: DesignTokens.hairline) : null,
        boxShadow: color == null ? DesignTokens.cardShadow : null,
      ),
      child: child,
    );
  }
}

class _RouteStep extends StatelessWidget {
  const _RouteStep({
    required this.label,
    required this.isCurrent,
    required this.isDone,
  });

  final String label;
  final bool isCurrent;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final color = isCurrent
        ? DesignTokens.primary
        : isDone
        ? DesignTokens.success
        : DesignTokens.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            isDone
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style:
                DesignTokens.body(
                  13,
                  weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ).copyWith(
                  color: isCurrent ? DesignTokens.ink : DesignTokens.mutedDim,
                ),
          ),
          if (isCurrent) ...[
            const Spacer(),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: DesignTokens.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
