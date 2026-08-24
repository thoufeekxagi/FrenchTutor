import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../providers/tutor_helper_provider.dart';
import '../services/tutor_helper_settings.dart';

/// Reusable Settings panel for the helper. The panel edits all surfaces, but
/// each row persists independently through TutorHelperSettings.
class TutorHelperSettingsPanel extends ConsumerWidget {
  const TutorHelperSettingsPanel({super.key, this.dark = false});

  final bool dark;

  Color get _textColor => dark ? DesignTokens.nightText : DesignTokens.ink;

  Color get _mutedColor =>
      dark ? DesignTokens.nightMuted : DesignTokens.mutedDim;

  Color get _surfaceColor =>
      dark ? DesignTokens.nightSurface : DesignTokens.surface;

  Color get _borderColor =>
      dark ? DesignTokens.nightHairline : DesignTokens.hairline;

  Color get _accentColor =>
      dark ? DesignTokens.nightAccent : DesignTokens.primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(tutorHelperSettingsProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_in_talk_rounded, size: 19, color: _accentColor),
              const SizedBox(width: 8),
              Text(
                'Tutor helper',
                style: DesignTokens.body(
                  15,
                  weight: FontWeight.w800,
                ).copyWith(color: _textColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose where your tutor can give bounded help. These settings are independent by practice area.',
            style: DesignTokens.body(
              11.5,
            ).copyWith(color: _mutedColor, height: 1.3),
          ),
          const SizedBox(height: 8),
          for (final surface in TutorHelperSurface.values) ...[
            _surfaceRow(
              settings: settings,
              surface: surface,
              isEnabled: settings.isEnabled(surface),
            ),
            if (surface != TutorHelperSurface.values.last)
              Divider(height: 1, color: _borderColor),
          ],
        ],
      ),
    );
  }

  Widget _surfaceRow({
    required TutorHelperSettings settings,
    required TutorHelperSurface surface,
    required bool isEnabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  surface.label,
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: _textColor),
                ),
                const SizedBox(height: 2),
                Text(
                  surface.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    10.5,
                  ).copyWith(color: _mutedColor, height: 1.2),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            onChanged: (value) =>
                unawaited(settings.setEnabled(surface, value)),
            activeThumbColor: _accentColor,
          ),
        ],
      ),
    );
  }
}
