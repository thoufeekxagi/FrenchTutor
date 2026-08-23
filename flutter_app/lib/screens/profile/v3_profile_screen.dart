import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import '../../services/auth_service.dart';
import '../../services/learning_streak_service.dart';
import '../history/all_history_screen.dart';
import '../notes/notes_review_screen.dart';
import '../progress/progress_screen.dart';
import '../speak/french_fingerprint_screen.dart';
import '../speak/speak_roadmap_screen.dart';
import '../speak/streak_calendar_screen.dart';
import '../speak/v3_settings_screen.dart';
import '../../widgets/v3/v3_surface.dart';

class V3ProfileScreen extends ConsumerWidget {
  const V3ProfileScreen({super.key, this.onBack, this.onReplayPractice});

  final VoidCallback? onBack;
  final VoidCallback? onReplayPractice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(learningStoreProvider).profile();
    final sessions = ref.watch(storageServiceProvider).getAllSessions();
    final streak = LearningStreakService.summarize(sessions);
    final level = LearnerLevel.displayLabel(profile.level);
    final name = AuthService.shared.signedInDisplayName;

    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          V3Header(
            title: 'Profile',
            subtitle: '$level · French learner',
            leading: V3BackButton(onPressed: onBack),
            trailing: V3IconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onPressed: () => AppRouter.push(
                context,
                (_) => V3SettingsScreen(onReplayPractice: onReplayPractice),
              ),
            ),
          ),
          const SizedBox(height: 18),
          V3Card(
            raised: true,
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: DesignTokens.nightAccentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    name.isEmpty ? 'F' : name.substring(0, 1).toUpperCase(),
                    style: DesignTokens.display(
                      24,
                    ).copyWith(color: DesignTokens.nightAccent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: DesignTokens.display(
                          22,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your learning identity and progress in one place.',
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: DesignTokens.nightMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          V3SectionLabel('Your progress'),
          const SizedBox(height: 9),
          Row(
            children: [
              _metric(
                icon: Icons.local_fire_department_rounded,
                value: '${streak.currentDays}',
                label: 'day streak',
              ),
              const SizedBox(width: 9),
              _metric(
                icon: Icons.route_rounded,
                value: '${sessions.length}',
                label: 'sessions',
              ),
              const SizedBox(width: 9),
              _metric(
                icon: Icons.flag_rounded,
                value: level,
                label: 'current level',
              ),
            ],
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Learning shortcuts'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.local_fire_department_rounded,
            title: 'Streak & calendar',
            subtitle: streak.currentDays == 0
                ? 'Build a consistent practice rhythm'
                : '${streak.currentDays}-day practice streak',
            onTap: () =>
                AppRouter.push(context, (_) => const StreakCalendarScreen()),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.bookmark_rounded,
            title: 'Saved lines',
            subtitle: 'Phrases and words you chose to revisit',
            onTap: () =>
                AppRouter.push(context, (_) => const NotesReviewScreen()),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.insights_rounded,
            title: 'Progress review',
            subtitle: 'See what is becoming easier over time',
            onTap: () => AppRouter.push(context, (_) => const ProgressScreen()),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.fingerprint_rounded,
            title: 'French fingerprint',
            subtitle: 'Your personal map of words and practice',
            onTap: () =>
                AppRouter.push(context, (_) => const FrenchFingerprintScreen()),
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Your course'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.menu_book_rounded,
            title: 'French pathway',
            subtitle: 'Your adaptive 20-session learning block',
            value: level,
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakRoadmapScreen()),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.history_rounded,
            title: 'Practice history',
            subtitle: 'Replay a completed lesson or speaking session',
            onTap: () =>
                AppRouter.push(context, (_) => const AllHistoryScreen()),
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: V3Card(
        padding: const EdgeInsets.fromLTRB(10, 13, 10, 12),
        child: Column(
          children: [
            Icon(icon, color: DesignTokens.nightAccent, size: 21),
            const SizedBox(height: 7),
            Text(
              value,
              style: DesignTokens.display(
                20,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: DesignTokens.body(
                10,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
          ],
        ),
      ),
    );
  }
}
