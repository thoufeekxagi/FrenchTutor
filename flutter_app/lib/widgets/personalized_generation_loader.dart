import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// A calm, honest waiting state for AI-generated lessons.
///
/// Generation time is not predictable enough to fake a percentage. Instead we
/// show one indeterminate progress track and a short rotating explanation of
/// the work being done. This keeps the learner oriented without adding a
/// second progress system or pretending that the model has completed a step it
/// has not.
class PersonalizedGenerationLoader extends StatefulWidget {
  const PersonalizedGenerationLoader({
    super.key,
    required this.content,
    this.detail,
    this.icon = CupertinoIcons.wand_stars,
    this.compact = false,
  });

  /// A human-readable content name, such as "grammar class" or "roleplay".
  final String content;
  final String? detail;
  final IconData icon;
  final bool compact;

  @override
  State<PersonalizedGenerationLoader> createState() =>
      _PersonalizedGenerationLoaderState();
}

class _PersonalizedGenerationLoaderState
    extends State<PersonalizedGenerationLoader> {
  Timer? _messageTimer;
  int _messageIndex = 0;

  List<String> get _messages => [
    'Reading your learning profile',
    'Choosing the right situation and dialogue for you',
    'Tailoring the French practice to your level',
  ];

  @override
  void initState() {
    super.initState();
    _messageTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.compact ? 16.0 : 24.0;
    final vertical = widget.compact ? 16.0 : 26.0;
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
          Container(
            width: widget.compact ? 48 : 60,
            height: widget.compact ? 48 : 60,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              color: DesignTokens.primary,
              size: widget.compact ? 21 : 26,
            ),
          ),
          SizedBox(height: widget.compact ? 12 : 16),
          AnimatedSwitcher(
            duration: DesignTokens.durationFast,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              '${_messages[_messageIndex]}…',
              key: ValueKey(_messageIndex),
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                widget.compact ? 13 : 15,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Your personalized ${widget.content} is rendering',
            textAlign: TextAlign.center,
            style: DesignTokens.display(widget.compact ? 18 : 22),
          ),
          if (widget.detail != null && widget.detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              widget.detail!,
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                widget.compact ? 12 : 13,
              ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
            ),
          ],
          SizedBox(height: widget.compact ? 15 : 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: DesignTokens.primarySoft,
              color: DesignTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}
