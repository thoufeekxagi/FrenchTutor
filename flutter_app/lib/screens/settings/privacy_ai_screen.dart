import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../services/ai_privacy_preferences.dart';
import '../../widgets/v3/v3_surface.dart';

/// The persistent, user-facing explanation of the AI data flows.
///
/// This is intentionally an explanation surface rather than a second consent
/// gate. The first-use gate records consent; this screen lets the learner
/// inspect the same providers and purposes later from Profile > Settings.
class PrivacyAiScreen extends StatefulWidget {
  const PrivacyAiScreen({super.key});

  @override
  State<PrivacyAiScreen> createState() => _PrivacyAiScreenState();
}

class _PrivacyAiScreenState extends State<PrivacyAiScreen> {
  AiPrivacySnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await AiPrivacyPreferences.read();
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _openPolicy() async {
    await launchUrl(
      Uri.parse('https://parlesprint.com/privacy'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openSupport() async {
    await launchUrl(Uri.parse('mailto:support@parlesprint.com'));
  }

  Future<void> _showDetails({
    required String title,
    required String provider,
    required String detail,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          decoration: BoxDecoration(
            color: DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DesignTokens.nightMuted.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(title, style: DesignTokens.display(22)),
              const SizedBox(height: 9),
              Text(
                provider,
                style: DesignTokens.label(
                  12,
                ).copyWith(color: DesignTokens.nightAccent),
              ),
              const SizedBox(height: 10),
              Text(
                detail,
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.nightMuted, height: 1.5),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: DesignTokens.primary,
                    foregroundColor: DesignTokens.onPrimary,
                    minimumSize: const Size(0, 50),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          const V3Header(
            title: 'Privacy & AI',
            subtitle: 'Review what is shared with your tutor',
            leading: V3BackButton(),
          ),
          const SizedBox(height: 18),
          V3Card(
            leadingAccent: true,
            leadingAccentAttached: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            child: Text(
              'Your lessons use only the information needed to create the selected experience. Tap any row to see what is sent and why.',
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.5),
            ),
          ),
          const SizedBox(height: 22),
          const V3SectionLabel('AI practice'),
          const SizedBox(height: 9),
          _dataRow(
            icon: CupertinoIcons.mic_fill,
            title: 'Voice practice',
            subtitle: 'Google Gemini Live',
            status: snapshot?.voice == true ? 'Allowed' : 'Not enabled',
            onTap: () => _showDetails(
              title: 'Voice practice',
              provider: 'Google Gemini Live',
              detail:
                  'Your microphone audio is sent during a live session so the tutor can reply in real time. The resulting transcript is saved with the session so it can support feedback and review.',
            ),
          ),
          const SizedBox(height: 8),
          _dataRow(
            icon: CupertinoIcons.text_bubble_fill,
            title: 'Text lessons & reviews',
            subtitle: 'Google Gemini or OpenRouter',
            status: snapshot?.text == true ? 'Allowed' : 'Not enabled',
            onTap: () => _showDetails(
              title: 'Text lessons & reviews',
              provider: 'Google Gemini or OpenRouter',
              detail:
                  'Selected lesson context, answers, and progress signals are sent to generate course content, feedback, warm-ups, and personalized reviews. Only the context needed for that request is included.',
            ),
          ),
          const SizedBox(height: 8),
          _dataRow(
            icon: CupertinoIcons.doc_text_viewfinder,
            title: 'Photos & PDFs',
            subtitle: 'Only when you choose Scan',
            status: snapshot?.media == true ? 'Allowed' : 'Not enabled',
            onTap: () => _showDetails(
              title: 'Photos & PDFs',
              provider: 'Sent only after you choose Scan',
              detail:
                  'A photo or PDF is sent for explanation only after you start a scan. It is not included in ordinary course, practice, or review requests.',
            ),
          ),
          const SizedBox(height: 8),
          _dataRow(
            icon: CupertinoIcons.sparkles,
            title: 'Generated audio or images',
            subtitle: 'ElevenLabs / MiniMax',
            status: 'On request',
            onTap: () => _showDetails(
              title: 'Generated audio or images',
              provider: 'ElevenLabs for audio · MiniMax for images',
              detail:
                  'A short description of the selected lesson and its learning targets may be sent when the app needs generated audio or an image. The app does not send your entire learning history for this request.',
            ),
          ),
          const SizedBox(height: 22),
          _dataRow(
            icon: CupertinoIcons.chart_bar_fill,
            title: 'Product analytics',
            subtitle: 'PostHog, when enabled',
            status: 'Optional',
            onTap: () => _showDetails(
              title: 'Product analytics',
              provider: 'PostHog and optional website analytics',
              detail:
                  'Limited interaction and technical data may be used to measure performance and improve the product. Lesson content, microphone audio, photos, and PDFs are not used for this purpose.',
            ),
          ),
          const SizedBox(height: 22),
          const V3SectionLabel('Your controls'),
          const SizedBox(height: 9),
          V3Card(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  color: DesignTokens.nightAccent,
                  size: 23,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can review these choices anytime. Your course and practice history are kept separate from this setting.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.nightMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.delete_outline_rounded,
            title: 'Delete account and learning data',
            subtitle: 'Available from Account settings',
            accent: DesignTokens.danger,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 22),
          TextButton(
            onPressed: _openPolicy,
            child: const Text('See the full privacy policy'),
          ),
          TextButton(
            onPressed: _openSupport,
            child: const Text('Contact support'),
          ),
        ],
      ),
    );
  }

  Widget _dataRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
    required VoidCallback onTap,
  }) {
    return V3Card(
      leadingAccent: true,
      leadingAccentAttached: true,
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: DesignTokens.nightAccent, size: 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
          Text(
            status,
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.nightAccent),
          ),
          const SizedBox(width: 5),
          Icon(
            Icons.chevron_right_rounded,
            color: DesignTokens.nightMuted,
            size: 20,
          ),
        ],
      ),
    );
  }
}
