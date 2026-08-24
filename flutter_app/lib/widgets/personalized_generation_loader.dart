import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// A calm, honest waiting state for AI-generated lessons.
///
/// Generation time is not predictable enough to fake a percentage. The loader
/// uses one indeterminate progress track, one short title, and one supporting
/// line. Keeping the copy to those two levels prevents the learner from
/// seeing several versions of the same “personalizing” message at once.
class PersonalizedGenerationLoader extends StatelessWidget {
  const PersonalizedGenerationLoader({
    super.key,
    required this.content,
    this.detail,
    this.icon = Icons.route_rounded,
    this.compact = false,
  });

  /// A human-readable content name, such as "grammar class" or "roleplay".
  final String content;
  final String? detail;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final horizontal = compact ? 16.0 : 22.0;
    final vertical = compact ? 16.0 : 20.0;
    final title = 'Preparing $content';
    final subtitle = detail?.trim().isNotEmpty == true
        ? detail!.trim()
        : 'Using your level and goals to choose the next activity.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _GenerationMark(icon: icon, compact: compact),
              SizedBox(width: compact ? 14 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.display(compact ? 18 : 21),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        compact ? 12 : 13,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 15 : 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: compact ? 5 : 6,
              backgroundColor: DesignTokens.primarySoft,
              color: DesignTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerationMark extends StatelessWidget {
  const _GenerationMark({required this.icon, required this.compact});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final diameter = compact ? 48.0 : 58.0;
    return SizedBox.square(
      dimension: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: diameter,
            child: CircularProgressIndicator(
              strokeWidth: compact ? 2.2 : 2.5,
              color: DesignTokens.primary,
              backgroundColor: DesignTokens.primarySoft,
            ),
          ),
          Container(
            width: diameter - 10,
            height: diameter - 10,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: DesignTokens.primary, size: 22),
          ),
        ],
      ),
    );
  }
}
