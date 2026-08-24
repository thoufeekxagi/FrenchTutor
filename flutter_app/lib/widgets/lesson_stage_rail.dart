import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// A compact, consistent lesson roadmap. The active and completed steps use
/// the shared accent so the rail follows both appearance modes.
class LessonStageRail extends StatelessWidget {
  const LessonStageRail({
    super.key,
    required this.labels,
    required this.currentIndex,
    this.onIndexTap,
  });

  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int>? onIndexTap;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final safeIndex = currentIndex.clamp(0, labels.length - 1).toInt();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onIndexTap == null ? null : () => onIndexTap!(index),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 6,
                    decoration: BoxDecoration(
                      color: index <= safeIndex
                          ? DesignTokens.primary
                          : DesignTokens.hairline,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: DesignTokens.label(9).copyWith(
                      color: index <= safeIndex
                          ? DesignTokens.primary
                          : DesignTokens.mutedDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (index != labels.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}
