import 'package:flutter/material.dart';

/// Five-card horizontal lanes for saved practice cards.
///
/// Each lane contains at most [maxColumns] cards. The lane scrolls horizontally
/// on narrow screens, while a new lane starts after the fifth card so a library
/// can keep growing without collapsing into tiny two-column cards. Stores
/// return history newest-first for "continue" surfaces, so this widget reverses
/// the visual order by default: new cards append at the end instead of pushing
/// the old fifth card into the next lane.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.maxColumns = 5,
    this.maxCardWidth = 180,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 18,
    this.mainAxisExtent = 244,
    this.newestAtEnd = true,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int maxColumns;
  final double maxCardWidth;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double mainAxisExtent;

  /// Whether the incoming newest-first list should be displayed oldest-first.
  /// Set this to false only when [itemBuilder] already receives items in the
  /// intended visual order.
  final bool newestAtEnd;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    final rowCount = (itemCount + maxColumns - 1) ~/ maxColumns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) SizedBox(height: mainAxisSpacing),
          SizedBox(
            height: mainAxisExtent,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(right: crossAxisSpacing),
              itemCount: ((itemCount - row * maxColumns).clamp(0, maxColumns)),
              separatorBuilder: (_, _) => SizedBox(width: crossAxisSpacing),
              itemBuilder: (context, index) {
                final visualIndex = row * maxColumns + index;
                final itemIndex = newestAtEnd
                    ? itemCount - visualIndex - 1
                    : visualIndex;
                return SizedBox(
                  width: maxCardWidth,
                  height: mainAxisExtent,
                  child: itemBuilder(context, itemIndex),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
