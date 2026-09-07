import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/content_models.dart';

/// The "tap a word to see its meaning" panel shared by Reading, Course, and
/// Listening (see story_reader_screen.dart and listening_practice_screen.dart)
/// — one look, one behavior, everywhere a learner can tap a French word.
/// Shows only the word and its meaning (a short phrase; a few short senses
/// separated by commas for a genuinely ambiguous word, never a sentence or
/// paragraph — this is a tap-and-glance panel, not a dictionary entry) and
/// an optional "Conjugate" action.
class WordMeaningOverlay extends StatelessWidget {
  const WordMeaningOverlay({
    super.key,
    required this.word,
    required this.accent,
    required this.darkMode,
    this.onConjugate,
  });

  final VocabEntry word;
  final Color accent;
  final bool darkMode;
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
