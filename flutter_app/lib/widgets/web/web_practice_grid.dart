import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'web_layout.dart';

class WebPracticeShortcut {
  const WebPracticeShortcut({
    required this.icon,
    required this.label,
    required this.locked,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool locked;
  final VoidCallback onTap;
}

class WebPracticeGrid extends StatelessWidget {
  const WebPracticeGrid({
    super.key,
    required this.items,
    this.heading = 'QUICK PRACTICE',
    this.description =
        'Choose one skill. Your next recommendation will reflect it.',
  });

  final List<WebPracticeShortcut> items;
  final String heading;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: DesignTokens.mono(
                      10,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.info, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
                  ),
                ],
              ),
            ),
            Text(
              '${items.length} ways to practise',
              style: DesignTokens.body(12).copyWith(color: DesignTokens.muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        WebCardGrid(
          minTileWidth: 180,
          spacing: 12,
          children: [
            for (final item in items)
              WebCard(
                onTap: item.onTap,
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 118),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: item.locked
                                  ? DesignTokens.canvasDim
                                  : DesignTokens.primarySoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              item.locked
                                  ? CupertinoIcons.lock_fill
                                  : item.icon,
                              size: 18,
                              color: item.locked
                                  ? DesignTokens.muted
                                  : DesignTokens.primary,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            item.locked
                                ? CupertinoIcons.lock_fill
                                : CupertinoIcons.arrow_up_right,
                            size: 14,
                            color: DesignTokens.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.body(14, weight: FontWeight.w700)
                            .copyWith(
                              color: item.locked
                                  ? DesignTokens.mutedDim
                                  : DesignTokens.ink,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
