import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/content_models.dart';

/// One short example sentence showing a tapped word used in context, in
/// French with its English translation.
typedef WordMeaningExample = ({String fr, String en});

/// The "tap a word to see its meaning" panel shared by Reading, Course, and
/// Listening (see story_reader_screen.dart and listening_practice_screen.dart)
/// — one look, one behavior, everywhere a learner can tap a French word.
/// Shows the word, its contextual meaning, up to two short usage examples,
/// and an optional "Conjugate" action.
class WordMeaningOverlay extends StatelessWidget {
  const WordMeaningOverlay({
    super.key,
    required this.word,
    required this.accent,
    required this.darkMode,
    this.examples = const [],
    this.onConjugate,
  });

  final VocabEntry word;
  final Color accent;
  final bool darkMode;
  final List<WordMeaningExample> examples;
  final VoidCallback? onConjugate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          word.fr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesignTokens.display(
            24,
          ).copyWith(color: Colors.white, height: 1.05),
        ),
        const SizedBox(height: 3),
        Text(
          word.en,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesignTokens.body(
            14,
          ).copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.25),
        ),
        for (final example in examples.take(2)) ...[
          const SizedBox(height: 6),
          Text(
            example.fr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignTokens.body(12, weight: FontWeight.w600).copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.2,
            ),
          ),
          if (example.en.isNotEmpty)
            Text(
              example.en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                11,
              ).copyWith(color: Colors.white.withValues(alpha: 0.6)),
            ),
        ],
        if (onConjugate != null) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              onTap: onConjugate,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'Conjugate  →',
                  style: DesignTokens.body(12, weight: FontWeight.w800)
                      .copyWith(
                        color: darkMode
                            ? DesignTokens.nightCanvas
                            : Colors.white,
                      ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
