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
    return ColoredBox(
      color: DesignTokens.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.space5,
              DesignTokens.space5,
              DesignTokens.space5,
              DesignTokens.space4,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 40,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: 'Close result',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onDone,
                          child: const SizedBox(
                            width: DesignTokens.minTapTarget,
                            height: DesignTokens.minTapTarget,
                            child: Icon(CupertinoIcons.xmark),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    Text('Session complete', style: DesignTokens.display(30)),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      'Speaking · argumentation',
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: DesignTokens.secondary),
                    ),
                    const SizedBox(height: DesignTokens.space5),
                    Text(
                      _description,
                      style: DesignTokens.body(
                        16,
                      ).copyWith(color: DesignTokens.mutedDim, height: 1.5),
                    ),
                    const SizedBox(height: DesignTokens.space5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.space4,
                      ),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                        border: Border.all(color: DesignTokens.hairline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ResultMetric(
                              value: _formatDuration(durationSeconds),
                              label: 'connected',
                              icon: CupertinoIcons.clock,
                            ),
                          ),
                          _metricDivider(),
                          Expanded(
                            child: _ResultMetric(
                              value: '$learnerTurns',
                              label: learnerTurns == 1
                                  ? 'learner turn'
                                  : 'learner turns',
                              icon: CupertinoIcons.waveform,
                            ),
                          ),
                          _metricDivider(),
                          const Expanded(
                            child: _ResultMetric(
                              value: 'Saved',
                              label: 'transcript',
                              icon: CupertinoIcons.doc_text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space6),
                    Text('What changes next', style: DesignTokens.display(20)),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      _practiceText,
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DesignTokens.space4),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                        border: Border.all(color: DesignTokens.hairline),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.book,
                            color: DesignTokens.primary,
                            size: 20,
                          ),
                          const SizedBox(width: DesignTokens.space3),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Next: Grammar · 12 min',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Strengthen the structures you used today',
                                  style: TextStyle(
                                    color: DesignTokens.mutedDim,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: DesignTokens.space8),
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

  Widget _metricDivider() {
    return Container(width: 1, height: 48, color: DesignTokens.hairline);
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
        Icon(icon, color: DesignTokens.secondary, size: 18),
        const SizedBox(height: DesignTokens.space2),
        Text(value, style: DesignTokens.display(20)),
        const SizedBox(height: DesignTokens.space1),
        Text(
          label,
          textAlign: TextAlign.center,
          style: DesignTokens.body(11).copyWith(color: DesignTokens.mutedDim),
        ),
      ],
    );
  }
}
