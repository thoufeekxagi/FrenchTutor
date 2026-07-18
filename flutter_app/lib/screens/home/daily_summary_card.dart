import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/daily_summary_service.dart';
import '../../widgets/kicker_text.dart';

/// "What today bought you" — the visible-value card (P1.4). Renders the
/// on-device DailySummary: words practiced, the ones that fought back (and
/// will return tomorrow), pronunciation focus, writing score, real speaking
/// minutes. Hidden entirely until the day has any activity.
class DailySummaryCard extends StatelessWidget {
  const DailySummaryCard({super.key, required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    if (!summary.hasActivity) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KickerText('Today so far', color: Passeport.slateDim),
              const Spacer(),
              Text(
                '${summary.stagesCompleted}/${summary.stagesTotal} stages',
                style: Passeport.mono(
                  11,
                  weight: FontWeight.w600,
                ).copyWith(color: Passeport.maroon),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statRow(),
          if (summary.wordsPracticed.isNotEmpty) ...[
            const SizedBox(height: 12),
            _wordChips(),
          ],
          if (summary.hardWords.isNotEmpty) ...[
            const SizedBox(height: 12),
            _hardWordsBlock(),
          ],
          if (summary.pronunciationFocus.isNotEmpty) ...[
            const SizedBox(height: 12),
            _pronunciationBlock(),
          ],
        ],
      ),
    );
  }

  Widget _statRow() {
    final stats = <(IconData, String)>[
      if (summary.wordsPracticed.isNotEmpty)
        (
          CupertinoIcons.rectangle_stack_fill,
          '${summary.wordsPracticed.length} word${summary.wordsPracticed.length == 1 ? '' : 's'}',
        ),
      if (summary.speakingSeconds > 0)
        (
          CupertinoIcons.mic_fill,
          '${(summary.speakingSeconds / 60).ceil()} min spoken',
        ),
      if (summary.learnerUtterances > 0)
        (CupertinoIcons.bubble_left_fill, '${summary.learnerUtterances} replies'),
      if (summary.writingScore != null)
        (
          CupertinoIcons.pencil_outline,
          'writing ${summary.writingScore!.toStringAsFixed(1)}/10',
        ),
      if (summary.sceneTitle != null)
        (CupertinoIcons.person_2_fill, 'Scene: ${summary.sceneTitle}'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final (icon, label) in stats)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Passeport.sage),
              const SizedBox(width: 5),
              Text(
                label,
                style: Passeport.body(
                  12,
                  weight: FontWeight.w600,
                ).copyWith(color: Passeport.inkSoft),
              ),
            ],
          ),
      ],
    );
  }

  Widget _wordChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final word in summary.wordsPracticed.take(8))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Passeport.parchmentDim,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              word.fr,
              style: Passeport.body(
                11.5,
                weight: FontWeight.w600,
              ).copyWith(color: Passeport.ink),
            ),
          ),
        if (summary.wordsPracticed.length > 8)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              '+${summary.wordsPracticed.length - 8} more',
              style: Passeport.body(11).copyWith(color: Passeport.slateDim),
            ),
          ),
      ],
    );
  }

  Widget _hardWordsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fought back today — returning tomorrow',
          style: Passeport.body(
            11.5,
            weight: FontWeight.w700,
          ).copyWith(color: Passeport.maroon),
        ),
        const SizedBox(height: 6),
        for (final hard in summary.hardWords)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Text(
                  hard.entry.fr,
                  style: Passeport.body(12.5, weight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hard.entry.en,
                    overflow: TextOverflow.ellipsis,
                    style: Passeport.body(
                      11.5,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pronunciationBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pronunciation focus',
          style: Passeport.body(
            11.5,
            weight: FontWeight.w700,
          ).copyWith(color: Passeport.sky),
        ),
        const SizedBox(height: 6),
        for (final tag in summary.pronunciationFocus)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '• ${tag.description}',
              style: Passeport.body(11.5).copyWith(color: Passeport.inkSoft),
            ),
          ),
      ],
    );
  }
}
