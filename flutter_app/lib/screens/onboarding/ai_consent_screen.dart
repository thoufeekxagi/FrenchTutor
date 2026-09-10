import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../services/ai_privacy_preferences.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= DesignTokens.breakpointExpanded) {
          return _desktopLayout();
        }
        return _mobileLayout();
      },
    );
  }

  Widget _desktopLayout() {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: Row(
        children: [
          Expanded(flex: 5, child: _desktopIntro()),
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
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                        border: Border.all(color: DesignTokens.hairline),
                        boxShadow: DesignTokens.surfaceShadow,
                      ),
                      child: _details(onDark: false, centered: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopIntro() {
    return DecoratedBox(
      decoration: BoxDecoration(color: DesignTokens.ink),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(72, 56, 56, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ParleSprint',
                style: DesignTokens.body(
                  16,
                  weight: FontWeight.w700,
                ).copyWith(color: Colors.white),
              ),
              const Spacer(),
              Text(
                'Privacy\n& AI.',
                style: DesignTokens.display(42, weight: FontWeight.w700)
                    .copyWith(
                      color: Colors.white,
                      height: 1.08,
                      letterSpacing: -1.1,
                    ),
              ),
              const SizedBox(height: 20),
              Text(
                'Review what is shared with your tutor before you begin.',
                style: DesignTokens.body(17).copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: DesignTokens.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'You can review the full policy anytime.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: Colors.white.withValues(alpha: 0.62)),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'AI PRACTICE  /  CLEAR CONTROLS',
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

  Widget _mobileLayout() {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: _details(onDark: false, centered: false),
        ),
      ),
    );
  }

  Widget _details({required bool onDark, required bool centered}) {
    final primaryText = onDark ? Colors.white : DesignTokens.ink;
    final secondaryText = onDark
        ? Colors.white.withValues(alpha: 0.78)
        : DesignTokens.mutedDim;
    final panelColor = onDark
        ? Colors.white.withValues(alpha: 0.13)
        : DesignTokens.canvas;
    final linkColor = onDark ? Colors.white : DesignTokens.primary;
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Icon(
          CupertinoIcons.chat_bubble_2_fill,
          size: 30,
          color: onDark ? Colors.white : DesignTokens.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Privacy & AI',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: DesignTokens.display(27).copyWith(color: primaryText),
        ),
        const SizedBox(height: 10),
        Text(
          'Review what is shared with your tutor before you begin.',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: DesignTokens.body(
            14,
          ).copyWith(color: secondaryText, height: 1.45),
        ),
        const SizedBox(height: 28),
        Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : DesignTokens.hairline,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 3,
                  child: ColoredBox(
                    color: onDark ? Colors.white : DesignTokens.primary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _consentPoint(
                      CupertinoIcons.mic_fill,
                      'Voice',
                      'Sent to Google Gemini Live for real-time tutor replies and a transcript.',
                      onDark,
                    ),
                    const SizedBox(height: 18),
                    _consentPoint(
                      CupertinoIcons.text_bubble_fill,
                      'Text & progress',
                      'Sent to Google Gemini or OpenRouter, which may route to OpenAI, for lessons, feedback, and review.',
                      onDark,
                    ),
                    const SizedBox(height: 18),
                    _consentPoint(
                      CupertinoIcons.doc_text_viewfinder,
                      'Photos & PDFs',
                      'Sent to Google Gemini only when you choose Scan for an explanation.',
                      onDark,
                    ),
                    const SizedBox(height: 18),
                    _consentPoint(
                      CupertinoIcons.sparkles,
                      'Generated media',
                      'Limited lesson context is sent to ElevenLabs for audio or MiniMax for images.',
                      onDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://parlesprint.com/privacy'),
              mode: LaunchMode.externalApplication,
            ),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: linkColor,
            ),
            child: const Text('See the full privacy policy'),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => _accept(),
            style: ElevatedButton.styleFrom(
              backgroundColor: DesignTokens.primary,
              foregroundColor: DesignTokens.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              ),
              textStyle: DesignTokens.body(15, weight: FontWeight.w700),
            ),
            child: const Text('Agree and continue'),
          ),
        ),
      ],
    );
  }

  Widget _consentPoint(
    IconData icon,
    String title,
    String detail,
    bool onDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onDark
                ? Colors.white.withValues(alpha: 0.10)
                : DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 17,
            color: onDark ? Colors.white : DesignTokens.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: DesignTokens.body(
                  14,
                  weight: FontWeight.w700,
                ).copyWith(color: onDark ? Colors.white : DesignTokens.ink),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: DesignTokens.body(13).copyWith(
                  color: onDark
                      ? Colors.white.withValues(alpha: 0.76)
                      : DesignTokens.mutedDim,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
