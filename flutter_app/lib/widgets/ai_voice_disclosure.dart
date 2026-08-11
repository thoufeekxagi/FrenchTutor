import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/app_styles.dart';
import '../screens/onboarding/ai_consent_screen.dart';

/// By the time any screen reaches this call, [AiConsentScreen] has already
/// gated the whole app on the same consent flag, so in practice this is a
/// no-op safety net (kept in case a future screen is reachable before that
/// gate is re-checked). If it ever does need to ask, it uses the exact same
/// plain-language copy and the exact same key as the app-level screen.
class AiVoiceDisclosure {
  AiVoiceDisclosure._();

  static const _prefsKey = AiConsentScreen.prefsKey;

  /// Returns true once the user has accepted (now, or on a previous call).
  /// Returns false if they decline — callers must not open the microphone
  /// or start the live call in that case.
  static Future<bool> ensureAccepted(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) == true) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Before you talk to your tutor'),
          content: const Text(
            'What you say and write is sent to Google to power your AI '
            "tutor and give you feedback. We don't sell your data.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Continue',
                style: TextStyle(
                  color: DesignTokens.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (accepted == true) {
      await prefs.setBool(_prefsKey, true);
      return true;
    }
    return false;
  }
}
