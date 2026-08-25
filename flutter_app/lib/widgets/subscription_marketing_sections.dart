import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Scrollable, proof-free value sections used below the subscription choices.
/// These explain what the learner is buying without inventing ratings,
/// testimonials, or outcome statistics before the app has real evidence.
class SubscriptionMarketingSections extends StatelessWidget {
  const SubscriptionMarketingSections({super.key});

  @override
  Widget build(BuildContext context) {
    // Register this flow with the inherited theme so a mode toggle rebuilds
    // the const paywall subtree and re-resolves all semantic tokens.
    Theme.of(context);
    return Column(
      children: [
        _LearningRouteCard(),
        SizedBox(height: DesignTokens.space5),
        _PersonalizationComparisonCard(),
        SizedBox(height: DesignTokens.space5),
        _ContextLearningCard(),
      ],
    );
  }
}

class _LearningRouteCard extends StatelessWidget {
  const _LearningRouteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A route from first French to confident B1',
            style: DesignTokens.display(24),
          ),
          const SizedBox(height: 8),
          Text(
            'Your level, goal, and practice evidence shape what comes next. The route grows with you instead of making you repeat a fixed course.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 184,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
                Positioned(left: 8, bottom: 42, child: _LevelTag('A1')),
                Positioned(left: 116, bottom: 92, child: _LevelTag('A2')),
                Positioned(right: 18, top: 18, child: _LevelTag('B1')),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Text(
                    'Start with what you know',
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Text(
                    'Next route',
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8, size.height - 56)
      ..cubicTo(
        size.width * 0.28,
        size.height - 56,
        size.width * 0.33,
        size.height - 18,
        size.width * 0.48,
        size.height - 76,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height - 132,
        size.width * 0.78,
        size.height - 62,
        size.width - 8,
        22,
      );
    final paint = Paint()
      ..color = DesignTokens.mastery
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = DesignTokens.surface;
    for (final point in [
      Offset(8, size.height - 56),
      Offset(size.width * 0.48, size.height - 76),
      Offset(size.width - 8, 22),
    ]) {
      canvas.drawCircle(point, 6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LevelTag extends StatelessWidget {
  const _LevelTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: DesignTokens.body(
          14,
          weight: FontWeight.w800,
        ).copyWith(color: DesignTokens.primaryReadable),
      ),
    );
  }
}

class _PersonalizationComparisonCard extends StatelessWidget {
  const _PersonalizationComparisonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Built around your reason for learning',
            style: DesignTokens.display(23),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a goal such as TEF/TCF, work, relocation, or daily French. Future lessons keep that context in view.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ComparisonColumn(
                  title: 'Preset-only route',
                  icon: Icons.close_rounded,
                  iconColor: DesignTokens.muted,
                  bullets: [
                    'Same sequence for everyone',
                    'Generic situations',
                    'Progress stops at the template',
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ComparisonColumn(
                  title: 'Your ParleSprint route',
                  icon: Icons.check_rounded,
                  iconColor: DesignTokens.success,
                  highlighted: true,
                  bullets: [
                    'Next lessons adapt to you',
                    'Useful situations and exam goals',
                    'Six skills work together',
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonColumn extends StatelessWidget {
  const _ComparisonColumn({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.bullets,
    this.highlighted = false,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> bullets;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? DesignTokens.primarySoft : DesignTokens.canvasDim,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DesignTokens.body(14, weight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final bullet in bullets) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    bullet,
                    style: DesignTokens.body(12.5).copyWith(height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ContextLearningCard extends StatelessWidget {
  const _ContextLearningCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        children: [
          Text(
            'Learn words inside real moments',
            textAlign: TextAlign.center,
            style: DesignTokens.display(23),
          ),
          const SizedBox(height: 7),
          Text(
            'A short story can lead to vocabulary, audio, grammar, and a practice turn—so you know when to use the French you learned.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: DesignTokens.hairline),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MiniTag('A1'),
                    const SizedBox(width: 8),
                    Text('Au marché', style: DesignTokens.display(20)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'At the market · a useful first conversation',
                  textAlign: TextAlign.center,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ContextFeature(Icons.volume_up_rounded, 'Audio'),
                    _ContextFeature(Icons.menu_book_rounded, 'Words'),
                    _ContextFeature(Icons.forum_rounded, 'Speak'),
                    _ContextFeature(Icons.refresh_rounded, 'Review'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: DesignTokens.body(
          12,
          weight: FontWeight.w800,
        ).copyWith(color: DesignTokens.info),
      ),
    );
  }
}

class _ContextFeature extends StatelessWidget {
  const _ContextFeature(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: DesignTokens.primary, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: DesignTokens.body(
            11,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.primary),
        ),
      ],
    );
  }
}

/// Repeats the selected offer after the educational story sections so the
/// learner never has to scroll back to find the purchase action.
class SubscriptionBottomOffer extends StatelessWidget {
  const SubscriptionBottomOffer({
    super.key,
    required this.price,
    required this.terms,
    required this.ctaLabel,
    required this.onTap,
    this.loading = false,
  });

  final String price;
  final String terms;
  final String ctaLabel;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        children: [
          Text(
            price,
            textAlign: TextAlign.center,
            style: DesignTokens.display(21),
          ),
          const SizedBox(height: 4),
          Text(
            terms,
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              13,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: onTap == null
                    ? DesignTokens.canvasDim
                    : DesignTokens.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                loading ? 'Processing…' : ctaLabel,
                style: DesignTokens.body(16, weight: FontWeight.w800).copyWith(
                  color: onTap == null
                      ? DesignTokens.mutedDim
                      : DesignTokens.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 16,
                color: DesignTokens.mutedDim,
              ),
              const SizedBox(width: 6),
              Text(
                'Secure via App Store · Cancel anytime',
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
