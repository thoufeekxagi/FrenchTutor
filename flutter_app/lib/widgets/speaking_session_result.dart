import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../design/app_styles.dart';
import 'primary_action_button.dart';

class SpeakingSessionResultView extends StatelessWidget {
  const SpeakingSessionResultView({
    super.key,
    required this.durationSeconds,
    required this.learnerTurns,
    required this.meetsCompletionThreshold,
    required this.isDailyPath,
    required this.onDone,
  });

  final int durationSeconds;
  final int learnerTurns;
  final bool meetsCompletionThreshold;
  final bool isDailyPath;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final completed = !isDailyPath || meetsCompletionThreshold;
    return ColoredBox(
      color: AppStyles.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 44,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: completed
                            ? AppStyles.successSoft
                            : AppStyles.infoSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        completed
                            ? CupertinoIcons.checkmark_alt
                            : CupertinoIcons.pause_fill,
                        color: completed ? AppStyles.success : AppStyles.info,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      completed ? 'Practice saved' : 'Good start, keep going',
                      style: AppStyles.display(30),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _description,
                      style: AppStyles.body(
                        16,
                      ).copyWith(color: AppStyles.mutedDim, height: 1.45),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppStyles.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: DesignTokens.surfaceShadow,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ResultMetric(
                              value: _formatDuration(durationSeconds),
                              label: 'connected',
                              icon: CupertinoIcons.clock_fill,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 54,
                            color: AppStyles.hairline,
                          ),
                          Expanded(
                            child: _ResultMetric(
                              value: '$learnerTurns',
                              label: learnerTurns == 1
                                  ? 'French turn'
                                  : 'French turns',
                              icon: CupertinoIcons.waveform,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDailyPath && meetsCompletionThreshold
                            ? AppStyles.successSoft
                            : AppStyles.infoSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isDailyPath && meetsCompletionThreshold
                                ? CupertinoIcons.arrow_up_right
                                : CupertinoIcons.book_fill,
                            color: isDailyPath && meetsCompletionThreshold
                                ? AppStyles.success
                                : AppStyles.info,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _practiceText,
                              style: AppStyles.body(
                                13.5,
                                weight: FontWeight.w500,
                              ).copyWith(color: AppStyles.inkSoft, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 32),
                    PrimaryActionButton(label: 'Done', onPressed: onDone),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _description {
    if (isDailyPath && meetsCompletionThreshold) {
      return 'You used today’s learning in conversation. Your speaking step is complete.';
    }
    if (isDailyPath) {
      return 'Your transcript is saved, but this step needs a little more spoken practice to complete.';
    }
    return 'Your conversation with Marie and its transcript are now in your journal.';
  }

  String get _practiceText {
    if (isDailyPath && meetsCompletionThreshold) {
      return 'Daily path updated from real speaking time and learner turns.';
    }
    if (isDailyPath) {
      return 'Resume later for more speaking practice. Nothing has been marked complete yet.';
    }
    return 'Transcript saved to Recent practice. No pronunciation score was invented.';
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppStyles.info, size: 19),
        const SizedBox(height: 8),
        Text(value, style: AppStyles.display(24)),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppStyles.body(12).copyWith(color: AppStyles.mutedDim),
        ),
      ],
    );
  }
}
