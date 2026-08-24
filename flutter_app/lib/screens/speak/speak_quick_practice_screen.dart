import 'package:flutter/material.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/vocab_lab_screen.dart';
import 'speak_free_talk_screen.dart';

/// Small, focused activities from the Speak Practice tab. No tutor portrait
/// takes over this surface; the tutor remains an entry point at the bottom.
class SpeakQuickPracticeScreen extends StatelessWidget {
  const SpeakQuickPracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: DesignTokens.nightText,
                  ),
                ),
                const SizedBox(width: 4),
                Text('Quick lessons', style: _display(25)),
                const Spacer(),
                Icon(
                  Icons.local_fire_department_rounded,
                  color: DesignTokens.nightAccent,
                ),
                const SizedBox(width: 5),
                Text('3', style: _body(13, weight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 24),
            Text('A few focused minutes', style: _display(28)),
            const SizedBox(height: 6),
            Text(
              'Refresh useful language between full speaking lessons.',
              style: _body(14).copyWith(color: DesignTokens.nightMuted),
            ),
            const SizedBox(height: 22),
            _quickCard(
              context,
              icon: Icons.translate_rounded,
              title: 'Vocabulary',
              subtitle: 'Review words you have recently met.',
              onTap: () => AppRouter.push(
                context,
                (_) => const VocabLabScreen(topic: 'Everyday French'),
                fullscreenDialog: true,
              ),
            ),
            const SizedBox(height: 10),
            _quickCard(
              context,
              icon: Icons.auto_awesome_rounded,
              title: 'Verbs',
              subtitle: 'Practise one useful action in context.',
              onTap: () => AppRouter.push(
                context,
                (_) => const GrammarLabScreen(topic: 'verbs'),
                fullscreenDialog: true,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => AppRouter.push(
                context,
                (_) => const SpeakFreeTalkScreen(),
                fullscreenDialog: true,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DesignTokens.nightSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: DesignTokens.nightHairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mic_none_rounded,
                      color: DesignTokens.nightAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ask your tutor',
                            style: _body(15, weight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Explain a phrase or start a scene.',
                            style: _body(
                              12,
                            ).copyWith(color: DesignTokens.nightMuted),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: DesignTokens.nightAccent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DesignTokens.nightAccentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: DesignTokens.nightAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _body(15, weight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: _body(12).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: DesignTokens.nightAccent),
          ],
        ),
      ),
    );
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);
}
