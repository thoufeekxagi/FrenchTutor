import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class WebAuthLayout extends StatelessWidget {
  const WebAuthLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: Row(
        children: [
          Expanded(flex: 5, child: _BrandPanel()),
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
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WebAuthFrame extends StatelessWidget {
  const WebAuthFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < DesignTokens.breakpointMedium) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: DesignTokens.ink),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(72, 56, 56, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Image.asset('assets/images/logo_mark.png'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'ParleSprint',
                    style: DesignTokens.body(
                      16,
                      weight: FontWeight.w700,
                    ).copyWith(color: Colors.white),
                  ),
                ],
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A clear path to\nmore confident French.',
                      style: DesignTokens.display(42, weight: FontWeight.w700)
                          .copyWith(
                            color: Colors.white,
                            height: 1.08,
                            letterSpacing: -1.2,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Practice what matters next, with a coach that keeps your progress grounded in real evidence.',
                      style: DesignTokens.body(17).copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const _RouteRow(
                      number: '01',
                      title: 'Start with the foundations',
                      detail: 'A guided first step, not a blank page.',
                    ),
                    const _RouteRow(
                      number: '02',
                      title: 'Build useful ability',
                      detail:
                          'Listening, speaking, reading, and writing together.',
                    ),
                    const _RouteRow(
                      number: '03',
                      title: 'See what changed',
                      detail:
                          'Progress that reflects practice you actually completed.',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'GUIDED MOMENTUM  /  FRENCH PRACTICE',
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
