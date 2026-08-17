import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../services/learning_streak_service.dart';
import '../history/all_history_screen.dart';
import '../notes/notes_review_screen.dart';
import 'speak_settings_screen.dart';
import 'speak_roadmap_screen.dart';
import 'streak_calendar_screen.dart';
import 'french_fingerprint_screen.dart';
import 'speak_ui.dart';

class SpeakProfileScreen extends ConsumerWidget {
  const SpeakProfileScreen({super.key, this.onBack});

  /// The tab returns to Home; when Profile is pushed from Settings, the
  /// normal navigator pop returns to Settings instead.
  final VoidCallback? onBack;

  void _goBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(learningStoreProvider).profile();
    final sessions = ref.watch(storageServiceProvider).getAllSessions();
    final name = 'French learner';
    final level = LearnerLevel.displayLabel(profile.level);
    final studiedSeconds = _actualStudySeconds(sessions);
    final streak = LearningStreakService.summarize(sessions);

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => _goBack(context),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () =>
                    AppRouter.push(context, (_) => const SpeakSettingsScreen()),
                icon: const Icon(
                  Icons.settings_rounded,
                  color: SpeakColors.inkSoft,
                  size: 23,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(child: Text(name, style: DesignTokens.display(25))),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Premium Member · $level',
              style: DesignTokens.body(12).copyWith(color: SpeakColors.inkSoft),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SpeakStat(
                icon: Icons.format_quote_rounded,
                value: '56',
                label: 'SENTENCES\nLIFETIME',
                color: DesignTokens.secondary,
              ),
              SpeakStat(
                icon: Icons.schedule_rounded,
                value: _formatStudyTime(studiedSeconds),
                label: 'TIME\nSTUDIED',
                color: SpeakColors.blue,
              ),
              SpeakStat(
                icon: Icons.local_fire_department_rounded,
                value:
                    '${streak.longestDays} ${streak.longestDays == 1 ? 'day' : 'days'}',
                label: 'LONGEST\nSTREAK',
                color: SpeakColors.orange,
              ),
            ],
          ),
          const SizedBox(height: 28),
          SpeakCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _profileRow(
                  context,
                  Icons.local_fire_department_rounded,
                  SpeakColors.orange,
                  'Streak & Calendar',
                  streak.currentDays == 0
                      ? 'Build a consistent practice rhythm'
                      : '${streak.currentDays}-day practice streak',
                  () => AppRouter.push(
                    context,
                    (_) => const StreakCalendarScreen(),
                  ),
                ),
                const Divider(height: 1, color: SpeakColors.line),
                _profileRow(
                  context,
                  Icons.bookmark_rounded,
                  SpeakColors.blue,
                  'Saved Lines',
                  'Phrases to review',
                  () =>
                      AppRouter.push(context, (_) => const NotesReviewScreen()),
                ),
                const Divider(height: 1, color: SpeakColors.line),
                _profileRow(
                  context,
                  Icons.fingerprint_rounded,
                  DesignTokens.secondary,
                  'Your French fingerprint',
                  'Your personal map of words and practice',
                  () => AppRouter.push(
                    context,
                    (_) => const FrenchFingerprintScreen(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SpeakSectionTitle(
            title: 'Your Courses',
            action: 'View all courses',
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakRoadmapScreen()),
          ),
          const SizedBox(height: 12),
          SpeakCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: SpeakColors.blueSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    color: SpeakColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'French',
                        style: DesignTokens.body(15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Survival French · $level',
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: SpeakColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded, color: SpeakColors.line),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () =>
                AppRouter.push(context, (_) => const AllHistoryScreen()),
            child: SpeakCard(
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: SpeakColors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Activities',
                      style: DesignTokens.body(14, weight: FontWeight.w700),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: SpeakColors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(
    BuildContext context,
    IconData icon,
    Color color,
    String title,
    String subtitle,
    VoidCallback? onTap,
  ) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    11.5,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, color: SpeakColors.inkSoft),
        ],
      ),
    );
    return onTap == null ? row : GestureDetector(onTap: onTap, child: row);
  }
}

int _actualStudySeconds(List<Session> sessions) {
  var seconds = 0;
  for (final session in sessions) {
    final startedAt = DateTime.tryParse(session.startedAt);
    final endedAt = session.endedAt == null
        ? null
        : DateTime.tryParse(session.endedAt!);
    if (startedAt == null || endedAt == null) continue;
    final elapsed = endedAt.difference(startedAt).inSeconds;
    if (elapsed > 0) seconds += elapsed;
  }
  return seconds;
}

String _formatStudyTime(int seconds) {
  if (seconds < 60) return '<1 min';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0 ? '$hours h' : '$hours h ${remainingMinutes}m';
}
