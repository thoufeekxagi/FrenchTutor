import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class WebOnboardingWelcome extends StatelessWidget {
  const WebOnboardingWelcome({super.key, required this.onContinue});

  final VoidCallback onContinue;

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
                    child: _welcomeCard(),
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
                'Start from where you are, practise what matters next, and keep the route visible.',
                style: DesignTokens.body(17).copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 40),
              const _RouteRow(
                number: '01',
                title: 'Tell us your starting point',
                detail: 'A few answers shape the first lesson.',
              ),
              const _RouteRow(
                number: '02',
                title: 'Practise with a real coach',
                detail: 'Speak, listen, read, and write together.',
              ),
              const _RouteRow(
                number: '03',
                title: 'Build from evidence',
                detail: 'Your next step changes as you practise.',
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

  Widget _welcomeCard() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.waveform,
              size: 21,
              color: DesignTokens.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Start with the French you actually need.',
            style: DesignTokens.display(
              28,
              weight: FontWeight.w700,
            ).copyWith(height: 1.15),
          ),
          const SizedBox(height: 10),
          Text(
            'Answer four quick questions and we will prepare a focused first step for you.',
            style: DesignTokens.body(
              15,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.5),
          ),
          const SizedBox(height: 28),
          Divider(height: 1, color: DesignTokens.hairline),
          const SizedBox(height: 20),
          for (final line in const [
            'No account needed to begin',
            'A route built around your goal',
            'You can change your choices later',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 16,
                    color: DesignTokens.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: DesignTokens.body(
                        13.5,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onContinue,
              icon: const Icon(CupertinoIcons.arrow_right, size: 17),
              label: const Text('Get started'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.primary,
                foregroundColor: DesignTokens.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    DesignTokens.radiusMedium,
                  ),
                ),
                textStyle: DesignTokens.body(15, weight: FontWeight.w700),
              ),
            ),
          ),
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
