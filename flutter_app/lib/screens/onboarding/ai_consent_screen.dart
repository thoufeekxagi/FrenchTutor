import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';

/// Apple Guideline 5.1.2(i) requires clear, upfront, standalone consent
/// before any personal data leaves the device for a third-party AI
/// processor — never bundled into a general Terms-of-Service acceptance,
/// and never gated on "has the user *seen* this" (that flag can go true on
/// first display and then never show again on a fresh install, which is a
/// real rejection reason). This gate is gated purely on "has the user
/// *accepted*", is its own screen, and blocks every AI feature in the app
/// until it is accepted. Same gradient/card language as the onboarding
/// welcome step so it reads as part of the app, not a bolted-on legal popup.
class AiConsentScreen extends StatelessWidget {
  const AiConsentScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  static const prefsKey = 'ai_data_consent_v1';

  static Future<bool> hasConsented() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) == true;
  }

  Future<void> _accept(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
    onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Icon(
                  CupertinoIcons.chat_bubble_2_fill,
                  size: 40,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
                const SizedBox(height: 18),
                Text(
                  'How your practice works',
                  textAlign: TextAlign.center,
                  style: DesignTokens.display(24).copyWith(color: Colors.white),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'ParleSprint sends what you say and write during '
                        'practice to Google, which powers your AI tutor '
                        'and gives you feedback.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          15,
                        ).copyWith(color: Colors.white, height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "We don't sell your data, and Google doesn't use "
                        'it to train its other products.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(15).copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('https://parlesprint.com/privacy'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(
                          'Read our full privacy policy',
                          style: DesignTokens.body(14, weight: FontWeight.w600)
                              .copyWith(
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _accept(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: DesignTokens.primaryDeep,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: DesignTokens.body(15, weight: FontWeight.w700),
                    ),
                    child: const Text('Agree and continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
