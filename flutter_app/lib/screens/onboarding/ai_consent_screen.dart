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

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
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
      decoration: const BoxDecoration(color: DesignTokens.ink),
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
                'Before we\nstart speaking.',
                style: DesignTokens.display(42, weight: FontWeight.w700)
                    .copyWith(
                      color: Colors.white,
                      height: 1.08,
                      letterSpacing: -1.1,
                    ),
              ),
              const SizedBox(height: 20),
              Text(
                'One clear note about how AI practice works, so you can choose with context.',
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
                    decoration: const BoxDecoration(
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
                'PRIVACY FIRST  /  CLEAR BY DESIGN',
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
          'How your practice works',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: DesignTokens.display(27).copyWith(color: primaryText),
        ),
        const SizedBox(height: 10),
        Text(
          'A short explanation before your first AI-powered lesson.',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: DesignTokens.body(
            14,
          ).copyWith(color: secondaryText, height: 1.45),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : DesignTokens.hairline,
            ),
          ),
          child: Column(
            children: [
              _consentPoint(
                '01',
                'Your practice powers feedback',
                'Audio, text, and answers from practice are sent to Google, which powers your AI tutor.',
                onDark,
              ),
              const SizedBox(height: 18),
              _consentPoint(
                '02',
                'Photos stay in your control',
                'If you use Live Vision Scan, photos or PDFs you choose are sent to Google for explanation. You decide when to share them.',
                onDark,
              ),
              const SizedBox(height: 18),
              _consentPoint(
                '03',
                'Your choice stays visible',
                "We don't sell your data, and Google doesn't use it to train its other products.",
                onDark,
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
            child: const Text('Read the full privacy policy'),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => _accept(),
            style: ElevatedButton.styleFrom(
              backgroundColor: onDark ? Colors.white : DesignTokens.primary,
              foregroundColor: onDark ? DesignTokens.primaryDeep : Colors.white,
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
    String number,
    String title,
    String detail,
    bool onDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: DesignTokens.mono(11, weight: FontWeight.w700).copyWith(
            color: onDark
                ? Colors.white.withValues(alpha: 0.66)
                : DesignTokens.primary,
          ),
        ),
        const SizedBox(width: 14),
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
