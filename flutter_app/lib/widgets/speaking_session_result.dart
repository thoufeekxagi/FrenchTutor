import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'passeport_primary_button.dart';

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
      color: Passeport.parchment,
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
                            ? Passeport.successSoft
                            : Passeport.infoSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        completed
                            ? CupertinoIcons.checkmark_alt
                            : CupertinoIcons.pause_fill,
                        color: completed ? Passeport.sage : Passeport.sky,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      completed ? 'Practice saved' : 'Good start—keep going',
                      style: Passeport.display(30),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _description,
                      style: Passeport.body(
                        16,
                      ).copyWith(color: Passeport.slateDim, height: 1.45),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Passeport.card,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: DesignTokens.cardShadow,
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
                            color: Passeport.hairline,
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
                            ? Passeport.successSoft
                            : Passeport.infoSoft,
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
                                ? Passeport.sage
                                : Passeport.sky,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _evidenceText,
                              style: Passeport.body(
                                13.5,
                                weight: FontWeight.w500,
                              ).copyWith(color: Passeport.inkSoft, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 32),
                    PasseportPrimaryButton(label: 'Done', onPressed: onDone),
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

  String get _evidenceText {
    if (isDailyPath && meetsCompletionThreshold) {
      return 'Daily path updated from real speaking time and learner turns.';
    }
    if (isDailyPath) {
      return 'Resume later to add enough speaking evidence. Nothing has been marked complete yet.';
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
        Icon(icon, color: Passeport.sky, size: 19),
        const SizedBox(height: 8),
        Text(value, style: Passeport.display(24)),
        const SizedBox(height: 3),
        Text(
          label,
          style: Passeport.body(12).copyWith(color: Passeport.slateDim),
        ),
      ],
    );
  }
}
