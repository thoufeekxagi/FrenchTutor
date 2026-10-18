import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_provider.dart';
import '../../services/learning_streak_service.dart';
import '../../widgets/v3/v3_surface.dart';
import '../ui/v3_ui.dart';

/// V3 presentation of the existing completed-session streak calculation.
class V3StreakCalendarScreen extends ConsumerWidget {
  const V3StreakCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(storageServiceProvider).getAllSessions();
    final streak = LearningStreakService.summarize(sessions);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final week = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final recentStart = today.subtract(const Duration(days: 34));
    final gridStart = recentStart.subtract(
      Duration(days: recentStart.weekday - 1),
    );
    final grid = List.generate(
      35,
      (index) => gridStart.add(Duration(days: index)),
    );

    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          V3Header(
            title: 'Your streak',
            subtitle: 'A day counts after one completed learning session.',
            leading: const V3BackButton(),
          ),
          const SizedBox(height: 12),
          V3Card(
            child: Row(
              children: [
                Expanded(
                  child: _metric(
                    context,
                    '${streak.currentDays}',
                    'day streak',
                    Icons.local_fire_department_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    context,
                    '${streak.longestDays}',
                    'longest streak',
                    Icons.emoji_events_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          V3Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This week', style: V3Type.title(20)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var index = 0; index < week.length; index++) ...[
                      if (index > 0) const SizedBox(width: 7),
                      Expanded(
                        child: _weekDay(
                          context,
                          week[index],
                          streak.isActiveOn(week[index]),
                          isToday: _sameDay(week[index], today),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          V3Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent activity', style: V3Type.title(20)),
                const SizedBox(height: 4),
                Text('Last 5 weeks', style: V3Type.body(13)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: Center(
                          child: Text(label, style: V3Type.strong(11)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: grid.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 7,
                    crossAxisSpacing: 7,
                  ),
                  itemBuilder: (context, index) {
                    final day = grid[index];
                    final visible =
                        !day.isAfter(today) && !day.isBefore(recentStart);
                    final active = visible && streak.isActiveOn(day);
                    return Semantics(
                      label:
                          '${_weekdayName(day.weekday)}, ${day.month}/${day.day}: '
                          '${active ? 'practice completed' : 'no completed practice'}',
                      child: Container(
                        decoration: BoxDecoration(
                          color: visible
                              ? (active
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: _sameDay(day, today)
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.5,
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: visible
                            ? Text(
                                '${day.day}',
                                style: V3Type.strong(
                                  10,
                                  active
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 13),
                Text(
                  streak.currentDays == 0
                      ? 'Finish one lesson or practice session to begin your streak.'
                      : 'Keep your rhythm going with one completed practice today.',
                  style: V3Type.body(13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(value, style: V3Type.title(27)),
        Text(label, style: V3Type.body(12)),
      ],
    ),
  );

  Widget _weekDay(
    BuildContext context,
    DateTime day,
    bool active, {
    required bool isToday,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label:
          '${_weekdayName(day.weekday)} ${day.day}, ${active ? 'complete' : 'not complete'}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isToday ? Border.all(color: primary) : null,
        ),
        child: Column(
          children: [
            Text(
              const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1],
              style: V3Type.body(10),
            ),
            const SizedBox(height: 5),
            Icon(
              active ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: active ? primary : Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayName(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];
}
