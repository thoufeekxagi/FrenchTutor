import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../widgets/web/web_layout.dart';
import '../history/all_history_screen.dart';
import '../history/history_screen.dart';
import '../path/path_screen.dart';

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

    if (MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded) {
      return _webProgress(
        context,
        skills: skills,
        week: week,
        days: days,
        categories: categories,
        recalledIds: recalledIds,
        recalledWords: recalledWords,
        recent: recent,
        hasSessions: sessions.isNotEmpty,
      );
    }

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
                ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
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
                'Your cumulative skill progress from completed work.',
              ),
              const SizedBox(height: DesignTokens.space5),
              ...skills.map(_buildSkill),
              const SizedBox(height: DesignTokens.space3),
              _buildNextRecommendation(context),
              const SizedBox(height: 32),

              _sectionHeading(
                'Your 30-day rhythm',
                'How your recent sessions were distributed — not a mastery score.',
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

  Widget _webProgress(
    BuildContext context, {
    required List<SkillProgress> skills,
    required ({int streak, int sessionsThisWeek, int minutesThisWeek}) week,
    required List<({DateTime day, int categoriesDone})> days,
    required List<({String category, int count})> categories,
    required Set<String> recalledIds,
    required List<VocabEntry> recalledWords,
    required List<Session> recent,
    required bool hasSessions,
  }) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebPage(
          header: const WebPageHeader(
            title: 'Progress',
            subtitle: 'Evidence from the work you have completed.',
          ),
          children: [
            WebCardGrid(
              minTileWidth: 440,
              children: [WebCard(child: _buildWeekCard(week, days))],
            ),
            const SizedBox(height: DesignTokens.space6),
            const WebSectionHeader(title: 'Your 30-day rhythm'),
            WebCard(child: _buildCategoryBreakdown(categories)),
            if (recalledWords.isNotEmpty || recalledIds.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.space6),
              const WebSectionHeader(title: 'Recall evidence'),
              _buildRecallCard(recalledIds.length, recalledWords),
            ],
            const SizedBox(height: DesignTokens.space6),
            const WebSectionHeader(title: 'Mastery'),
            WebCard(
              child: Column(
                children: [
                  for (var index = 0; index < skills.length; index++) ...[
                    _buildSkill(skills[index]),
                    if (index < skills.length - 1)
                      Divider(color: DesignTokens.hairline),
                  ],
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space6),
            WebSectionHeader(
              title: 'Recent sessions',
              actionLabel: hasSessions ? 'View all' : null,
              onAction: hasSessions
                  ? () =>
                        AppRouter.push(context, (_) => const AllHistoryScreen())
                  : null,
            ),
            WebCard(child: _buildRecentSessions(context, recent)),
          ],
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
    return counts.entries
        .map((e) => (category: e.key, count: e.value))
        .toList();
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
          ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildWeekCard(
    ({int streak, int sessionsThisWeek, int minutesThisWeek}) week,
    List<({DateTime day, int categoriesDone})> days,
  ) {
    final planItems = days.fold<int>(
      0,
      (total, day) => total + day.categoriesDone,
    );
    return ModernCard(
      padding: DesignTokens.space5,
      child: Row(
        children: [
          _statTile('${week.minutesThisWeek}', 'Focused minutes'),
          _statTile('${week.sessionsThisWeek}', 'Sessions'),
          _statTile('$planItems', 'Plan items'),
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
            ).copyWith(color: DesignTokens.mutedDim),
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
    final state = skill.fraction >= 0.75
        ? 'Ready'
        : skill.fraction > 0
        ? 'Building'
        : 'Review';
    final stateColor = state == 'Review'
        ? DesignTokens.mutedDim
        : DesignTokens.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignTokens.infoSoft,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
            child: Icon(
              _iconForSkill(skill.name),
              size: 21,
              color: DesignTokens.primary,
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
                      state,
                      style: DesignTokens.label(11).copyWith(color: stateColor),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.space2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                  child: LinearProgressIndicator(
                    value: skill.fraction,
                    minHeight: 7,
                    backgroundColor: DesignTokens.canvasDim,
                    valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                  ),
                ),
                const SizedBox(height: DesignTokens.space2),
                Text(
                  skill.detail,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextRecommendation(BuildContext context) {
    return ModernCard(
      padding: DesignTokens.space5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT TO PRACTICE NEXT',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.primary, letterSpacing: 0.9),
          ),
          const SizedBox(height: DesignTokens.space2),
          Text('Structure an argument', style: DesignTokens.display(20)),
          const SizedBox(height: DesignTokens.space1),
          Text(
            '12 min · supports TEF speaking Part 2',
            style: DesignTokens.body(13).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: DesignTokens.space3),
          Text(
            'Strengthen the structures you used in your recent practice.',
            style: DesignTokens.body(
              13,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
          const SizedBox(height: DesignTokens.space4),
          OutlinedButton(
            onPressed: () => AppRouter.push(context, (_) => const PathScreen()),
            child: const Text('Open path'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(
    List<({String category, int count})> categories,
  ) {
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
          ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
        ),
      );
    }

    return ModernCard(
      padding: DesignTokens.space4,
      child: Column(
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const Divider(height: 20, color: DesignTokens.canvasDim),
            _categoryMetric(categories[i], total),
          ],
        ],
      ),
    );
  }

  Widget _categoryMetric(({String category, int count}) category, int total) {
    final percent = total == 0 ? 0 : (category.count / total * 100).round();
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DesignTokens.infoSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _iconForCategory(category.category),
            size: 18,
            color: DesignTokens.primary,
          ),
        ),
        const SizedBox(width: DesignTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.category,
                style: DesignTokens.body(14, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${category.count} session${category.count == 1 ? '' : 's'} · $percent% of recent practice',
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
        ),
        Text(
          '${category.count}',
          style: DesignTokens.mono(
            16,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.primary),
        ),
      ],
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
          ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
        ),
      );
    }
    return ModernCard(
      padding: DesignTokens.space2,
      child: Column(
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: DesignTokens.canvasDim),
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
