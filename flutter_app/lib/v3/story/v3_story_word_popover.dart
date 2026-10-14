import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../ui/v3_ui.dart';

/// The shared V3 word card used from both reading and listening transcripts.
/// It stays attached to the tapped word and does not reveal a gloss until the
/// learner asks for one.
class V3StoryWordPopover extends StatelessWidget {
  const V3StoryWordPopover({
    super.key,
    required this.anchor,
    required this.word,
    required this.meaning,
    required this.onDismiss,
    required this.onHear,
    this.pos = '',
    this.sound = '',
    this.gender = '',
    this.number = '',
  });

  final Rect anchor;
  final String word;
  final String meaning;
  final String pos;
  final String sound;
  final String gender;
  final String number;
  final VoidCallback onDismiss;
  final VoidCallback onHear;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(250.0, size.width - 32);
    final left = (anchor.center.dx - width / 2).clamp(
      16.0,
      size.width - 16 - width,
    );
    final arrowX = (anchor.center.dx - left - 7).clamp(18.0, width - 32);
    final above = anchor.top > 190;
    final morphology = [
      pos,
      _shortGender(gender),
      _shortNumber(number),
      sound,
    ].where((value) => value.isNotEmpty).join('  ·  ');

    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word, style: V3Type.strong(17)),
                const SizedBox(height: 2),
                Text(meaning, style: V3Type.body(14.5, DesignTokens.ink)),
                if (morphology.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(morphology, style: V3Type.body(12)),
                ],
              ],
            ),
          ),
          V3Pressable(
            key: const ValueKey('story.popover.hear'),
            label: 'Hear word',
            onTap: onHear,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                CupertinoIcons.speaker_2_fill,
                size: 20,
                color: DesignTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );

    final arrow = Positioned(
      left: arrowX,
      top: above ? null : -6,
      bottom: above ? -6 : null,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            border: Border(
              right: above
                  ? BorderSide(color: DesignTokens.hairline)
                  : BorderSide.none,
              bottom: above
                  ? BorderSide(color: DesignTokens.hairline)
                  : BorderSide.none,
              left: above
                  ? BorderSide.none
                  : BorderSide(color: DesignTokens.hairline),
              top: above
                  ? BorderSide.none
                  : BorderSide(color: DesignTokens.hairline),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('story.popover.dismiss'),
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          width: width,
          top: above ? null : anchor.bottom + 10,
          bottom: above ? size.height - anchor.top + 10 : null,
          child: Semantics(
            key: const ValueKey('story.popover'),
            container: true,
            label: 'Meaning of $word: $meaning',
            child: Material(
              type: MaterialType.transparency,
              child: Stack(clipBehavior: Clip.none, children: [card, arrow]),
            ),
          ),
        ),
      ],
    );
  }

  String _shortGender(String value) {
    switch (value.toLowerCase()) {
      case 'masculine':
        return 'M';
      case 'feminine':
        return 'F';
      case 'masculine or feminine':
      case 'masculine/feminine':
        return 'M/F';
      default:
        return '';
    }
  }

  String _shortNumber(String value) {
    switch (value.toLowerCase()) {
      case 'singular':
        return 'S';
      case 'plural':
        return 'P';
      default:
        return '';
    }
  }
}
