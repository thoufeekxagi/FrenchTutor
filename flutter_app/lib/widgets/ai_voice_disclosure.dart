import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/ai_privacy_preferences.dart';

/// A safety gate for screens that start a live voice session directly.
class AiVoiceDisclosure {
  AiVoiceDisclosure._();

  /// Reads the existing consent without prompting. Screens that want to
  /// connect Marie automatically may use this guard so a background lesson
  /// open never surprises the learner with a modal; an explicit tap still
  /// goes through [ensureAccepted] and can ask once when needed.
  static Future<bool> isAccepted() => AiPrivacyPreferences.canUseVoice();

  /// Returns true once the user has accepted (now, or on a previous call).
  /// Returns false if they decline — callers must not open the microphone
  /// or start the live call in that case.
  static Future<bool> ensureAccepted(BuildContext context) async {
    if (await AiPrivacyPreferences.canUseVoice()) return true;
    if (!context.mounted) return false;

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DesignTokens.muted.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enable your microphone',
                style: DesignTokens.display(22, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Speak with your tutor in real time. You can change this later in Settings.',
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
              ),
              const SizedBox(height: 16),
              Divider(color: DesignTokens.hairline, height: 1),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: DesignTokens.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your voice is sent to Google Gemini Live to generate tutor replies and a transcript.',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: FilledButton.styleFrom(
                        backgroundColor: DesignTokens.canvasDim,
                        foregroundColor: DesignTokens.inkSoft,
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: DesignTokens.primary,
                        foregroundColor: DesignTokens.onPrimary,
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (accepted == true) {
      await AiPrivacyPreferences.acceptAll();
      return true;
    }
    return false;
  }
}
