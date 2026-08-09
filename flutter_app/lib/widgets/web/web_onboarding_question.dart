import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class WebOnboardingQuestion extends StatelessWidget {
  const WebOnboardingQuestion({
    super.key,
    required this.step,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.children,
    required this.footer,
    this.subtitle,
  });

  final int step;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.canvas,
      child: Row(
        children: [
          Expanded(flex: 5, child: _brandPanel()),
          Expanded(
            flex: 6,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _questionCard(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DesignTokens.primaryDeep, DesignTokens.ink],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(72, 56, 56, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ParleSprint',
                style: DesignTokens.body(
                  16,
                  weight: FontWeight.w700,
                ).copyWith(color: Colors.white),
              ),
              const Spacer(),
              Text(
                'Build your route\nfrom here.',
                style: DesignTokens.display(42, weight: FontWeight.w700)
                    .copyWith(
                      color: Colors.white,
                      height: 1.08,
                      letterSpacing: -1.2,
                    ),
              ),
              const SizedBox(height: 20),
              Text(
                'A few clear choices help us start with the practice that matters most to you.',
                style: DesignTokens.body(17).copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 40),
              const _RouteRow(
                number: '01',
                title: 'Start with your goal',
                detail: 'Know what French should unlock.',
              ),
              const _RouteRow(
                number: '02',
                title: 'Set your starting point',
                detail: 'Choose a pace that feels honest.',
              ),
              const _RouteRow(
                number: '03',
                title: 'Make it yours',
                detail: 'Shape the coach around your life.',
              ),
              const Spacer(),
              Text(
                'GUIDED MOMENTUM  /  YOUR ROUTE',
                style: DesignTokens.mono(11, weight: FontWeight.w600).copyWith(
                  color: Colors.white.withValues(alpha: 0.45),
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionCard() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: DesignTokens.primary, size: 21),
              ),
              const Spacer(),
              Text(
                'Step $step of 4',
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (step / 4).clamp(0, 1),
              minHeight: 5,
              backgroundColor: DesignTokens.canvasDim,
              valueColor: const AlwaysStoppedAnimation(DesignTokens.primary),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            eyebrow.toUpperCase(),
            style: DesignTokens.mono(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.muted, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: DesignTokens.display(
              30,
              weight: FontWeight.w700,
            ).copyWith(height: 1.15),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
            ),
          ],
          const SizedBox(height: 28),
          ...children,
          const SizedBox(height: 8),
          footer,
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: DesignTokens.mono(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.secondary, letterSpacing: 1),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(
                    14,
                    weight: FontWeight.w700,
                  ).copyWith(color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: DesignTokens.body(13).copyWith(
                    color: Colors.white.withValues(alpha: 0.58),
                    height: 1.35,
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
