import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class WebCallLayout extends StatelessWidget {
  const WebCallLayout({
    super.key,
    required this.persona,
    required this.status,
    required this.statusColor,
    required this.duration,
    required this.onExit,
    required this.transcript,
    required this.controls,
    this.error,
  });

  final String persona;
  final String status;
  final Color statusColor;
  final String duration;
  final VoidCallback onExit;
  final Widget transcript;
  final Widget controls;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              persona: persona,
              status: status,
              statusColor: statusColor,
              duration: duration,
              onExit: onExit,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: DesignTokens.surface,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusCard,
                              ),
                              border: Border.all(color: DesignTokens.hairline),
                              boxShadow: DesignTokens.cardShadow,
                            ),
                            child: Column(
                              children: [
                                Expanded(child: transcript),
                                if (error != null)
                                  _ErrorBanner(message: error!),
                                controls,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 280,
                          child: _TutorRail(
                            persona: persona,
                            status: status,
                            statusColor: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.persona,
    required this.status,
    required this.statusColor,
    required this.duration,
    required this.onExit,
  });

  final String persona;
  final String status;
  final Color statusColor;
  final String duration;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        border: Border(bottom: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'End practice',
            onPressed: onExit,
            icon: const Icon(CupertinoIcons.xmark, size: 18),
            color: DesignTokens.mutedDim,
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 28, color: DesignTokens.hairline),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LIVE PRACTICE',
                style: DesignTokens.mono(
                  10,
                  weight: FontWeight.w700,
                ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
              ),
              const SizedBox(height: 3),
              Text(
                'Conversation with $persona',
                style: DesignTokens.display(18),
              ),
            ],
          ),
          const Spacer(),
          _StatusChip(status: status, color: statusColor),
          const SizedBox(width: 16),
          Text(
            duration,
            style: DesignTokens.mono(12).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: DesignTokens.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: DesignTokens.body(
              12,
              weight: FontWeight.w600,
            ).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _TutorRail extends StatelessWidget {
  const _TutorRail({
    required this.persona,
    required this.status,
    required this.statusColor,
  });

  final String persona;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DesignTokens.primaryDeep,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            alignment: Alignment.center,
            child: Text(
              persona.isEmpty ? '?' : persona.characters.first.toUpperCase(),
              style: DesignTokens.display(
                26,
                weight: FontWeight.w700,
              ).copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            persona,
            style: DesignTokens.display(
              22,
              weight: FontWeight.w700,
            ).copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: DesignTokens.body(
              13,
              weight: FontWeight.w600,
            ).copyWith(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 28),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
          const SizedBox(height: 24),
          Text(
            'A CALM CONVERSATION',
            style: DesignTokens.mono(10, weight: FontWeight.w700).copyWith(
              color: Colors.white.withValues(alpha: 0.52),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          for (final item in const [
            'Speak naturally',
            'Pause whenever you need',
            'Ask for a correction',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: Colors.white.withValues(alpha: 0.78)),
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: DesignTokens.body(
          12,
        ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
      ),
    );
  }
}
