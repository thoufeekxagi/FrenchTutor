import 'v3_talk_setup.dart';
import '../tests/v3_tests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../screens/mocks/mocks_screen.dart';
import '../ui/v3_ui.dart';

/// Tutor tab. Screen contract:
///
/// User arrived to: talk to the tutor.
/// They must understand: what their selected tutor can do for the exam.
/// Primary action: pick one mode.
/// Must not contain: a mascot carousel, settings sprawl, fake transcripts.
///
/// Each mode opens an existing, tested live screen. The tutor lesson-contract
/// session and the TCF examiner mode are built on these entries next.
class V3MarieScreen extends ConsumerWidget {
  const V3MarieScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(learningStoreProvider).profile().level;
    final band = const {'a1', 'a2', 'b1', 'b2'}.contains(level.toLowerCase())
        ? level.toUpperCase()
        : 'A1';
    return ValueListenableBuilder<TutorPersona>(
      valueListenable: ActiveTutor.notifier,
      builder: (context, tutor, _) => SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          children: [
            Text('TCF CANADA PRACTICE', style: V3Type.eyebrow()),
            const SizedBox(height: 6),
            Text(tutor.displayName, style: V3Type.hero(44)),
            const SizedBox(height: 22),
            _mode(
              context,
              id: 'talk',
              title: 'Practise French with ${tutor.displayName}',
              subtitle: 'Speak naturally and get helpful corrections.',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () =>
                  AppRouter.push(context, (_) => const V3TalkSetupScreen()),
            ),
            const SizedBox(height: 12),
            _mode(
              context,
              id: 'speaking',
              title: 'TCF speaking practice',
              subtitle: 'The three speaking tasks, timed like the exam.',
              icon: Icons.record_voice_over_outlined,
              onTap: () => openV3Exam(
                context,
                ref,
                (_) => MocksScreen(
                  examName: 'TCF Canada',
                  levelBand: band,
                  includeReadingWarmup: false,
                ),
                fullscreenDialog: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mode(
    BuildContext context, {
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return V3Pressable(
      key: ValueKey('marie.mode.$id'),
      label: title,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: DesignTokens.hairline),
          boxShadow: DesignTokens.surfaceShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: DesignTokens.primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V3Type.strong(17)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: V3Type.body(14)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: DesignTokens.inkSoft),
          ],
        ),
      ),
    );
  }
}
