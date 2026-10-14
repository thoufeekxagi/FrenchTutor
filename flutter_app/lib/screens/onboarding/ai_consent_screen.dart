import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../services/ai_privacy_preferences.dart';
import '../../v3/ui/v3_ui.dart';

/// Apple Guideline 5.1.2(i) requires clear, upfront, standalone consent
/// before any personal data leaves the device for a third-party AI
/// processor — never bundled into a general Terms-of-Service acceptance,
/// and never gated on "has the user *seen* this" (that flag can go true on
/// first display and then never show again on a fresh install, which is a
/// real rejection reason). This gate is gated purely on "has the user
/// *accepted*", is its own screen, and blocks every AI feature in the app
/// until it is accepted.
class AiConsentScreen extends StatelessWidget {
  const AiConsentScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  static const prefsKey = AiPrivacyPreferences.consentKey;

  static Future<bool> hasConsented() => AiPrivacyPreferences.hasConsented();

  Future<void> _accept() async {
    await AiPrivacyPreferences.acceptAll();
    onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    // Same look as onboarding on every screen size: the mark, one heading, the
    // four disclosures as rows, and one button that is always in reach. The
    // wording of the disclosures is unchanged.
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: V3Width(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: DesignTokens.hairline),
                          ),
                          child: Image.asset(
                            'assets/images/parlesprint_app_icon.png',
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'ParleSprint',
                          style: V3Type.strong(15, DesignTokens.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    Text('Privacy and AI', style: V3Type.title(36)),
                    const SizedBox(height: 8),
                    Text(
                      'What is shared with your tutor.',
                      style: V3Type.body(16),
                    ),
                    const SizedBox(height: 22),
                    _point(
                      CupertinoIcons.mic_fill,
                      'Voice',
                      'Sent to Google Gemini Live for real-time tutor replies and a transcript.',
                    ),
                    _point(
                      CupertinoIcons.text_bubble_fill,
                      'Text & progress',
                      'Sent to Google Gemini or OpenRouter, which may route to OpenAI, for lessons, feedback, and review.',
                    ),
                    _point(
                      CupertinoIcons.doc_text_viewfinder,
                      'Photos & PDFs',
                      'Sent to Google Gemini only when you choose Scan for an explanation.',
                    ),
                    _point(
                      CupertinoIcons.sparkles,
                      'Generated media',
                      'Limited lesson context is sent to ElevenLabs for audio or MiniMax for images.',
                      last: true,
                    ),
                    V3TextAction(
                      key: const ValueKey('consent.privacy'),
                      label: 'See the full privacy policy',
                      onTap: () => launchUrl(
                        Uri.parse('https://parlesprint.com/privacy'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: V3Button(
                  key: const ValueKey('consent.agree'),
                  label: 'Agree and continue',
                  onTap: () => _accept(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _point(
    IconData icon,
    String title,
    String detail, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: DesignTokens.hairline),
          bottom: last
              ? BorderSide(color: DesignTokens.hairline)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: DesignTokens.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: V3Type.strong(16)),
                const SizedBox(height: 3),
                Text(detail, style: V3Type.body(14, DesignTokens.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
