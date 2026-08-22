import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../design/tokens.dart';
import '../models/tutor_persona.dart';

class SpeakingSessionResultView extends StatelessWidget {
  const SpeakingSessionResultView({
    super.key,
    required this.durationSeconds,
    required this.learnerTurns,
    required this.meetsCompletionThreshold,
    required this.isDailyPath,
    required this.onDone,
    this.tutorName,
    this.practiceLabel,
  });

  final int durationSeconds;
  final int learnerTurns;
  final bool meetsCompletionThreshold;
  final bool isDailyPath;
  final VoidCallback onDone;
  final String? tutorName;
  final String? practiceLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedTutorName = tutorName ?? ActiveTutor.current.displayName;
    return ColoredBox(
      color: DesignTokens.nightCanvas,
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
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
                              child: Icon(
                                CupertinoIcons.xmark,
                                color: DesignTokens.nightMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      Text(
                        'Speaking complete',
                        style: DesignTokens.display(30).copyWith(
                          color: DesignTokens.nightText,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space2),
                      Text(
                        practiceLabel ?? 'Speaking practice',
                        style: DesignTokens.body(
                          14,
                        ).copyWith(color: DesignTokens.nightAccent),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      Text(
                        _description(resolvedTutorName),
                        style: DesignTokens.body(
                          16,
                        ).copyWith(color: DesignTokens.nightMuted, height: 1.5),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.space4,
                        ),
                        decoration: BoxDecoration(
                          color: DesignTokens.nightSurface,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusCard,
                          ),
                          border: Border.all(color: DesignTokens.nightHairline),
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
                      Text(
                        'What changes next',
                        style: DesignTokens.display(20).copyWith(
                          color: DesignTokens.nightText,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space2),
                      Text(
                        _practiceText,
                        style: DesignTokens.body(14).copyWith(
                          color: DesignTokens.nightMuted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      _nextPracticeRow(),
                      const Spacer(),
                      const SizedBox(height: DesignTokens.space8),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: onDone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DesignTokens.nightAccent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Back to Speaking Practice',
                            style: DesignTokens.body(
                              15,
                              weight: FontWeight.w800,
                            ).copyWith(color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricDivider() {
    return Container(width: 1, height: 48, color: DesignTokens.nightHairline);
  }

  Widget _nextPracticeRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space4,
        vertical: DesignTokens.space3,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DesignTokens.nightAccentSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              CupertinoIcons.book,
              color: DesignTokens.nightAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Grammar',
                      style: DesignTokens.body(16, weight: FontWeight.w700)
                          .copyWith(
                            color: DesignTokens.nightText,
                            decoration: TextDecoration.none,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '12 min',
                      style: DesignTokens.label(
                        11,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Strengthen the structures you used today',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _description(String resolvedTutorName) {
    if (isDailyPath && meetsCompletionThreshold) {
      return 'You used today’s learning in conversation. Your speaking step is complete.';
    }
    if (isDailyPath) {
      return 'Your transcript is saved, but this step needs a little more spoken practice to complete.';
    }
    return 'Your conversation with $resolvedTutorName and its transcript are now in your journal.';
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
        Icon(icon, color: DesignTokens.nightAccent, size: 18),
        const SizedBox(height: DesignTokens.space2),
        Text(
          value,
          style: DesignTokens.display(
            20,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: DesignTokens.space1),
        Text(
          label,
          textAlign: TextAlign.center,
          style: DesignTokens.body(11).copyWith(color: DesignTokens.nightMuted),
        ),
      ],
    );
  }
}
