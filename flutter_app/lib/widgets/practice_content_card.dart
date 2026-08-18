import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'learning_card.dart';

/// Shared library card for generated practice content.
///
/// Every practice tab supplies the same four pieces of learner-facing context:
/// an image, a title, a level, and a compact duration/count. The tab itself
/// already tells the learner whether the card is reading, writing, grammar,
/// vocabulary, listening, or roleplay, so the card does not repeat that label.
class PracticeContentCard extends StatelessWidget {
  const PracticeContentCard({
    super.key,
    required this.title,
    required this.levelBand,
    required this.meta,
    required this.onTap,
    this.summary,
    this.coverUrl,
    this.fallbackIcon = CupertinoIcons.book_fill,
  });

  final String title;
  final String levelBand;
  final String meta;
  final VoidCallback onTap;
  final String? summary;
  final String? coverUrl;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      padding: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: _PracticeArtwork(
                source: coverUrl,
                fallbackIcon: fallbackIcon,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.display(16),
                    ),
                    if (summary != null && summary!.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.body(
                          11.5,
                        ).copyWith(color: DesignTokens.mutedDim, height: 1.2),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${levelBand.trim().isEmpty ? 'A1' : levelBand}  •  $meta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeArtwork extends StatelessWidget {
  const _PracticeArtwork({required this.source, required this.fallbackIcon});

  final String? source;
  final IconData fallbackIcon;

  Widget _fallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
      child: Center(child: Icon(fallbackIcon, color: Colors.white, size: 34)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = source?.trim();
    if (value == null || value.isEmpty) return _fallback();
    if (value.startsWith('asset:')) {
      return Image.asset(
        value.substring('asset:'.length),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return Image.network(
      value,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }
}
