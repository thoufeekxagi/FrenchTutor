import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/tutor_persona.dart';
import '../services/inline_call_controller.dart';
import 'inline_call_bar.dart';

/// Bounded tutor help for the Speaking lesson surface.
///
/// The switch controls whether the inline tutor is available. The phone action
/// starts/ends the existing Gemini Live call; it never changes the scripted
/// lesson, target phrase, or progression owned by the host screen.
class SpeakingMurrayBar extends StatelessWidget {
  const SpeakingMurrayBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onEnabledChanged,
  });

  final InlineCallController controller;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final tutor = ActiveTutor.current;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: DesignTokens.nightAccentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.phone_in_talk_rounded,
              size: 17,
              color: enabled
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tutor.displayName} help',
                  style: DesignTokens.body(13, weight: FontWeight.w800)
                      .copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'On by default · tap the phone for a hint in this lesson'
                      : 'Off · practise the regular session only',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    11,
                  ).copyWith(color: DesignTokens.nightMuted, height: 1.25),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onEnabledChanged,
            activeThumbColor: DesignTokens.nightAccent,
          ),
          if (enabled)
            InlineCallActions(
              controller: controller,
              accentColor: DesignTokens.nightAccent,
            ),
        ],
      ),
    );
  }
}
