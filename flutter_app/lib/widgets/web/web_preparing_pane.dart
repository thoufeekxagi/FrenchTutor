import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class WebPreparingPane extends StatefulWidget {
  const WebPreparingPane({
    super.key,
    required this.active,
    required this.checkpoints,
    required this.onComplete,
  });

  final bool active;
  final List<String> checkpoints;
  final VoidCallback onComplete;

  @override
  State<WebPreparingPane> createState() => _WebPreparingPaneState();
}

class _WebPreparingPaneState extends State<WebPreparingPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _completionTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener(_handleStatus);
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(WebPreparingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _completionTimer?.cancel();
    _completionTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = Curves.easeInOutCubic.transform(_controller.value);
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
                        child: _progressCard(progress),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _brandPanel() {
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
              Text(
                'Your learning path\nis taking shape.',
                style: DesignTokens.display(40, weight: FontWeight.w700)
                    .copyWith(
                      color: Colors.white,
                      height: 1.08,
                      letterSpacing: -1.1,
                    ),
              ),
              const SizedBox(height: 20),
              Text(
                'We are using the choices you just made to set up a focused first session.',
                style: DesignTokens.body(17).copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.55,
                ),
              ),
              const Spacer(),
              Text(
                'GUIDED MOMENTUM  /  FIRST SESSION',
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

  Widget _progressCard(double progress) {
    final visibleCount = (progress * (widget.checkpoints.length + 0.5)).floor();
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              CupertinoIcons.waveform,
              size: 20,
              color: DesignTokens.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Creating your first lessons…',
            style: DesignTokens.display(
              27,
              weight: FontWeight.w700,
            ).copyWith(height: 1.15),
          ),
          const SizedBox(height: 8),
          Text(
            'A short setup step. Your answers stay visible below.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 124,
                height: 124,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 124,
                      height: 124,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        color: DesignTokens.primary,
                        backgroundColor: DesignTokens.canvasDim,
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: DesignTokens.display(22, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.checkpoints.length; i++)
                      _checkpoint(widget.checkpoints[i], i < visibleCount),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Divider(height: 1, color: DesignTokens.hairline),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(
                CupertinoIcons.lock_shield_fill,
                size: 15,
                color: DesignTokens.mutedDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your path can update as you practise.',
                  style: DesignTokens.body(
                    12,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _checkpoint(String label, bool visible) {
    return AnimatedOpacity(
      duration: DesignTokens.durationMedium,
      opacity: visible ? 1 : 0.28,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(
              visible
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 17,
              color: visible ? DesignTokens.success : DesignTokens.muted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: DesignTokens.body(
                  13,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
