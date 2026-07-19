import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';

/// Apple Guideline 5.1.2(i) requires explicit, named, upfront consent before
/// any personal data (here: microphone audio) leaves the device to a
/// third-party AI processor — not consent buried in a general Terms of
/// Service. This gate shows that disclosure once, the first time the user
/// is about to start a live voice call, before the microphone ever opens.
class AiVoiceDisclosure {
  AiVoiceDisclosure._();

  static const _prefsKey = 'ai_voice_disclosure_accepted_v1';

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
            'To have a live conversation, your voice is streamed to '
            "Google's Gemini AI, which generates your tutor's spoken "
            'replies and grades your practice. Your written answers and '
            'progress may also be sent to Gemini (or, if you\'ve set one '
            'up, OpenRouter) for lesson generation and grading.\n\n'
            "We never sell your data. See parlesprint.com/privacy for the "
            'full privacy policy.',
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
