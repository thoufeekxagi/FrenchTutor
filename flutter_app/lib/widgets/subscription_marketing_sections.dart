import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../v3/ui/v3_ui.dart';

/// Scrollable TCF Canada value details shown below the plan and primary CTA.
/// Copy describes the course as it exists and makes no score or outcome claims.
class SubscriptionMarketingSections extends StatelessWidget {
  const SubscriptionMarketingSections({super.key});

  static const _features = [
    (
      icon: Icons.route_rounded,
      title: 'A guided level path',
      detail: 'Build your French through A1, A2, B1, and B2.',
    ),
    (
      icon: Icons.fact_check_outlined,
      title: 'One course for four skills',
      detail: 'Keep listening, speaking, reading, and writing in focus.',
    ),
    (
      icon: Icons.record_voice_over_outlined,
      title: 'Speaking with your tutor',
      detail: 'Choose the tutor you want to practise with.',
    ),
    (
      icon: Icons.refresh_rounded,
      title: 'Review as you learn',
      detail: 'Revisit vocabulary from your lessons with spaced practice.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHAT’S INCLUDED',
          style: DesignTokens.label(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1.5),
        ),
        const SizedBox(height: 7),
        Text(
          'A focused course for TCF Canada',
          style: DesignTokens.display(23),
        ),
        const SizedBox(height: 7),
        Text(
          'A clear French path, with practice connected to your exam goal.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Column(
            children: [
              for (var index = 0; index < _features.length; index++) ...[
                _FeatureRow(
                  icon: _features[index].icon,
                  title: _features[index].title,
                  detail: _features[index].detail,
                ),
                if (index < _features.length - 1)
                  Divider(height: 1, color: DesignTokens.hairline),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: DesignTokens.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(15, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Repeats the selected offer after the details, so the learner can purchase
/// without scrolling back to the plan cards.
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
        borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR SELECTED PLAN',
            style: DesignTokens.label(
              10.5,
              weight: FontWeight.w800,
            ).copyWith(color: DesignTokens.muted),
          ),
          const SizedBox(height: 5),
          Text(price, style: DesignTokens.display(25)),
          const SizedBox(height: 3),
          Text(
            terms,
            style: DesignTokens.body(
              12.5,
            ).copyWith(color: DesignTokens.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          V3Button(
            key: const ValueKey('paywall.purchase.bottom'),
            label: ctaLabel,
            onTap: onTap,
            loading: loading,
            trailingArrow: false,
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Secure via App Store · Cancel anytime',
              textAlign: TextAlign.center,
              style: DesignTokens.body(12).copyWith(color: DesignTokens.muted),
            ),
          ),
        ],
      ),
    );
  }
}
