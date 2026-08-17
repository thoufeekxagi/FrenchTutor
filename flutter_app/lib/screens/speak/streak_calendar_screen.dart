import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/learning_streak_service.dart';
import 'speak_ui.dart';

class StreakCalendarScreen extends ConsumerWidget {
  const StreakCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(storageServiceProvider).getAllSessions();
    final streak = LearningStreakService.summarize(sessions);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(
      today.weekday,
      (index) => weekStart.add(Duration(days: index)),
    );
    final activeThisWeek = weekDays.where(streak.isActiveOn).length;
    final firstVisibleDay = today.subtract(const Duration(days: 27));
    final gridStart = firstVisibleDay.subtract(
      Duration(days: firstVisibleDay.weekday - 1),
    );
    final lastVisibleDay = today.add(Duration(days: 7 - today.weekday));
    final gridDays = List.generate(
      lastVisibleDay.difference(gridStart).inDays + 1,
      (index) => gridStart.add(Duration(days: index)),
    );

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          SpeakHeader(
            title: 'Streak & Calendar',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _metric('${streak.currentDays}', 'Current streak'),
                    const SizedBox(width: 12),
                    _metric('${streak.longestDays}', 'Longest streak'),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  streak.currentDays == 0
                      ? 'Start a new rhythm with one completed practice today.'
                      : 'You have practised for ${streak.currentDays} '
                            '${streak.currentDays == 1 ? 'day' : 'days'} in a row.',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent activity', style: DesignTokens.display(20)),
                const SizedBox(height: 4),
                Text(
                  'A day is counted when you complete at least one lesson or conversation.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    _Weekday(label: 'M'),
                    _Weekday(label: 'T'),
                    _Weekday(label: 'W'),
                    _Weekday(label: 'T'),
                    _Weekday(label: 'F'),
                    _Weekday(label: 'S'),
                    _Weekday(label: 'S'),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  itemCount: gridDays.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final day = gridDays[index];
                    final inWindow = !day.isBefore(firstVisibleDay);
                    return _DayCell(
                      day: day,
                      active: inWindow && streak.isActiveOn(day),
                      current:
                          LearningStreakService.dayKey(day) ==
                          LearningStreakService.dayKey(today),
                      visible: inWindow && !day.isAfter(today),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const _LegendDot(active: true),
                    const SizedBox(width: 6),
                    Text(
                      'Practised',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                    const SizedBox(width: 16),
                    const _LegendDot(active: false),
                    const SizedBox(width: 6),
                    Text(
                      'No completed practice',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SpeakCard(
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: SpeakColors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This week: $activeThisWeek of ${weekDays.length} days practised',
                    style: DesignTokens.body(13, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SpeakColors.blueSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: DesignTokens.mono(26, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              label,
              style: DesignTokens.body(11).copyWith(color: SpeakColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _Weekday extends StatelessWidget {
  const _Weekday({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: DesignTokens.body(
        10,
        weight: FontWeight.w700,
      ).copyWith(color: SpeakColors.inkSoft),
    ),
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.active,
    required this.current,
    required this.visible,
  });

  final DateTime day;
  final bool active;
  final bool current;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final fill = active ? SpeakColors.blue : SpeakColors.line;
    return Container(
      decoration: BoxDecoration(
        color: visible ? fill : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: current
            ? Border.all(color: SpeakColors.blue, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: visible
          ? Text(
              '${day.day}',
              style: DesignTokens.body(
                10,
                weight: FontWeight.w700,
              ).copyWith(color: active ? Colors.white : SpeakColors.inkSoft),
            )
          : null,
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: active ? SpeakColors.blue : SpeakColors.line,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
