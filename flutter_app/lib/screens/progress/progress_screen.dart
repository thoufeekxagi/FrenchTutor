import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/content_service.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../services/daily_goal_service.dart';
import '../../services/progress_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/session_row.dart';
import '../history/all_history_screen.dart';
import '../history/history_screen.dart';

/// Practice history and evidence of progress — no duplicated checklist (that's
/// what "Today's mission" on the Today tab is for) and no legacy roadmap
/// month copy. Everything here reads from the same `sessions` table
/// [DailyGoalService]/[TodayMissionWidget] already use, so the numbers always
/// agree with what the learner just did.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressServiceProvider);
    final store = ref.watch(learningStoreProvider);
    final sessions = ref.watch(storageServiceProvider).getAllSessions();
    final skills = progress.skillProgress();

    final recalledIds = store
        .entriesRecalledSince(DateTime.now().subtract(const Duration(days: 7)))
        .toSet();
    final recalledWords = ContentService.shared.vocabPhases
        .expand((phase) => phase.themes.expand((theme) => theme.entries))
        .where((entry) => recalledIds.contains(entry.id))
        .take(6)
        .toList();

    final week = _weekStats(sessions, progress);
    final days = _dailyActivity(sessions);
    final categories = _categoryBreakdown(sessions);
    final recent = sessions.take(5).toList();

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: PSContentColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              DesignTokens.space6,
              DesignTokens.screenMargin,
              40,
            ),
            children: [
              Text('Progress', style: DesignTokens.display(30)),
              const SizedBox(height: DesignTokens.space2),
              Text(
                'See the practice behind your growing French.',
                style: DesignTokens.body(
                  16,
                ).copyWith(color: DesignTokens.slateDim, height: 1.4),
              ),
              const SizedBox(height: 28),

              _sectionHeading('This week', 'Your practice at a glance.'),
              const SizedBox(height: DesignTokens.space4),
              _buildWeekCard(week, days),
              const SizedBox(height: 32),

              if (recalledWords.isNotEmpty || recalledIds.isNotEmpty) ...[
                _sectionHeading(
                  'Recall evidence',
                  'Words you retrieved from memory without help.',
                ),
                const SizedBox(height: DesignTokens.space4),
                _buildRecallCard(recalledIds.length, recalledWords),
                const SizedBox(height: 32),
              ],

              _sectionHeading(
                'Mastery',
                'Measured from the work you have completed.',
              ),
              const SizedBox(height: DesignTokens.space5),
              ...skills.map(_buildSkill),
              const SizedBox(height: 12),

              _sectionHeading(
                'Practice by category',
                'Where your last 30 days of sessions went.',
              ),
              const SizedBox(height: DesignTokens.space4),
              _buildCategoryBreakdown(categories),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _sectionHeading(
                      'Recent sessions',
                      'Your last few practice sessions.',
                    ),
                  ),
                  if (sessions.isNotEmpty)
                    TextButton(
                      onPressed: () => AppRouter.push(
                        context,
                        (_) => const AllHistoryScreen(),
                      ),
                      child: Text(
                        'See all',
                        style: DesignTokens.body(
                          14,
                          weight: FontWeight.w600,
                        ).copyWith(color: DesignTokens.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.space2),
              _buildRecentSessions(context, recent),
            ],
          ),
        ),
      ),
    );
  }

  // --- Data shaping -------------------------------------------------------

  static ({int streak, int sessionsThisWeek, int minutesThisWeek}) _weekStats(
    List<Session> sessions,
    ProgressService progress,
  ) {
    final weekStart = DateTime.now().subtract(const Duration(days: 6));
    final thisWeek = sessions.where((s) {
      final started = DateTime.tryParse(s.startedAt);
      return started != null && !started.isBefore(_startOfDay(weekStart));
    }).toList();
    return (
      streak: DailyGoalService.streak(sessions),
      sessionsThisWeek: thisWeek.length,
      minutesThisWeek: progress.speakingMinutes(thisWeek),
    );
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<({DateTime day, int categoriesDone})> _dailyActivity(
    List<Session> sessions,
  ) {
    final today = DateTime.now();
    return List.generate(7, (index) {
      final day = today.subtract(Duration(days: 6 - index));
      return (
        day: day,
        categoriesDone: DailyGoalService.categoriesOn(sessions, day).length,
      );
    });
  }

  static List<({String category, int count})> _categoryBreakdown(
    List<Session> sessions,
  ) {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final counts = {for (final c in DailyGoalService.categories) c: 0};
    for (final session in sessions) {
      final started = DateTime.tryParse(session.startedAt);
      if (started == null || started.isBefore(since)) continue;
      final category = DailyGoalService.categoryFor(session.stage);
      if (category != null) counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts.entries.map((e) => (category: e.key, count: e.value)).toList();
  }

  // --- Sections -------------------------------------------------------

  Widget _sectionHeading(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DesignTokens.display(20)),
        const SizedBox(height: DesignTokens.space1),
        Text(
          description,
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.slateDim, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildWeekCard(
    ({int streak, int sessionsThisWeek, int minutesThisWeek}) week,
    List<({DateTime day, int categoriesDone})> days,
  ) {
    return PasseportCard(
      padding: DesignTokens.space5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statTile('${week.streak}', 'Day streak'),
              _statTile('${week.sessionsThisWeek}', 'Sessions'),
              _statTile('${week.minutesThisWeek}', 'Minutes'),
            ],
          ),
          const SizedBox(height: DesignTokens.space5),
          SizedBox(height: 116, child: _WeekActivityChart(days: days)),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: DesignTokens.mono(26, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            label,
            style: DesignTokens.body(
              12.5,
            ).copyWith(color: DesignTokens.slateDim),
          ),
        ],
      ),
    );
  }

  Widget _buildRecallCard(int recalledCount, List<VocabEntry> sampleWords) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recalledCount > 0
                ? 'You recalled $recalledCount word${recalledCount == 1 ? '' : 's'} from memory without help.'
                : 'Recall a word without help and your first progress update will appear here.',
            style: DesignTokens.body(
              16,
              weight: FontWeight.w600,
            ).copyWith(height: 1.4),
          ),
          if (sampleWords.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.space4),
            Wrap(
              spacing: DesignTokens.space2,
              runSpacing: DesignTokens.space2,
              children: sampleWords
                  .map(
                    (word) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.space3,
                        vertical: DesignTokens.space2,
                      ),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        word.fr,
                        style: DesignTokens.body(13, weight: FontWeight.w600),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkill(SkillProgress skill) {
    final percentage = (skill.fraction * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignTokens.successSoft,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
            child: Icon(
              _iconForSkill(skill.name),
              size: 21,
              color: DesignTokens.success,
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        skill.name,
                        style: DesignTokens.body(15, weight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$percentage%',
                      style: DesignTokens.body(
                        13,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.space2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                  child: LinearProgressIndicator(
                    value: skill.fraction,
                    minHeight: 7,
                    backgroundColor: DesignTokens.parchmentDim,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      DesignTokens.success,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.space2),
                Text(
                  skill.detail,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.slateDim, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<({String category, int count})> categories) {
    final total = categories.fold<int>(0, (sum, c) => sum + c.count);
    if (total == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignTokens.space5),
        decoration: BoxDecoration(
          color: DesignTokens.canvasDim,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: Text(
          'Practice a session in any category and it will show up here.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.slateDim, height: 1.4),
        ),
      );
    }

    return PasseportCard(
      padding: DesignTokens.space5,
      child: Column(
        children: categories.map((c) {
          final fraction = total > 0 ? c.count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.space4),
            child: Row(
              children: [
                Icon(_iconForCategory(c.category), size: 18, color: DesignTokens.primary),
                const SizedBox(width: DesignTokens.space3),
                SizedBox(
                  width: 84,
                  child: Text(
                    c.category,
                    style: DesignTokens.body(13.5, weight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      backgroundColor: DesignTokens.parchmentDim,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        DesignTokens.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.space3),
                SizedBox(
                  width: 26,
                  child: Text(
                    '${c.count}',
                    textAlign: TextAlign.right,
                    style: DesignTokens.mono(13, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecentSessions(BuildContext context, List<Session> recent) {
    if (recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignTokens.space5),
        decoration: BoxDecoration(
          color: DesignTokens.canvasDim,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: Text(
          'Your practice sessions will appear here once you complete one.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.slateDim, height: 1.4),
        ),
      );
    }
    return PasseportCard(
      padding: DesignTokens.space2,
      child: Column(
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: DesignTokens.parchmentDim),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppRouter.push(
                context,
                (_) => HistoryScreen(session: recent[i]),
              ),
              child: SessionRow(session: recent[i]),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForSkill(String name) {
    switch (name) {
      case 'Vocabulary':
        return CupertinoIcons.square_stack_3d_up;
      case 'Grammar':
        return CupertinoIcons.book;
      case 'Listening':
        return CupertinoIcons.headphones;
      case 'Writing':
        return CupertinoIcons.square_pencil;
      default:
        return CupertinoIcons.book_fill;
    }
  }

  IconData _iconForCategory(String category) => switch (category) {
    'Vocabulary' => CupertinoIcons.square_stack_3d_up,
    'Grammar' => CupertinoIcons.book,
    'Listening' => CupertinoIcons.headphones,
    'Roleplay' => CupertinoIcons.bubble_left_bubble_right,
    'Writing' => CupertinoIcons.square_pencil,
    _ => CupertinoIcons.waveform,
  };
}

/// A plain 7-bar activity chart — bar height is how many of the 6 daily-goal
/// categories were touched that day, out of 6. Same source as the Today
/// tab's mission dots, just shown across a week instead of one day.
class _WeekActivityChart extends StatelessWidget {
  const _WeekActivityChart({required this.days});

  final List<({DateTime day, int categoriesDone})> days;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return LayoutBuilder(
      builder: (context, constraints) {
        final barAreaHeight = constraints.maxHeight - 30;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: days.map((entry) {
            final isToday =
                entry.day.year == today.year &&
                entry.day.month == today.month &&
                entry.day.day == today.day;
            final fraction = (entry.categoriesDone / 6).clamp(0.0, 1.0);
            final barHeight = (barAreaHeight * fraction).clamp(
              entry.categoriesDone > 0 ? 6.0 : 2.0,
              barAreaHeight,
            );
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: DesignTokens.durationMedium,
                      curve: DesignTokens.curveStandard,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: entry.categoriesDone > 0
                            ? (isToday ? DesignTokens.primary : DesignTokens.primarySoft)
                            : DesignTokens.canvasDim,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      DateFormat('EEEEE').format(entry.day),
                      style: DesignTokens.body(
                        11,
                        weight: isToday ? FontWeight.w700 : FontWeight.w500,
                      ).copyWith(
                        color: isToday ? DesignTokens.primary : DesignTokens.slateDim,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
