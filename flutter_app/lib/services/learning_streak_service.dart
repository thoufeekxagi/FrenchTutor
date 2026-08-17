import '../models/session.dart';

/// A calm consistency measure backed by completed learning sessions.
///
/// A day counts when the learner completes at least one saved session. This
/// deliberately measures continuity, not volume or a fixed set of activities.
class LearningStreak {
  const LearningStreak({
    required this.currentDays,
    required this.longestDays,
    required this.activeDayKeys,
  });

  final int currentDays;
  final int longestDays;
  final Set<String> activeDayKeys;

  bool isActiveOn(DateTime day) =>
      activeDayKeys.contains(LearningStreakService.dayKey(day));
}

class LearningStreakService {
  const LearningStreakService._();

  static LearningStreak summarize(List<Session> sessions, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    final activeDays = <String>{};

    for (final session in sessions) {
      // A session is only a real practice day once it has been finished.
      if (session.endedAt == null) continue;
      final started = DateTime.tryParse(session.startedAt)?.toLocal();
      if (started != null) activeDays.add(dayKey(started));
    }

    return LearningStreak(
      currentDays: _currentStreak(activeDays, today),
      longestDays: _longestStreak(activeDays),
      activeDayKeys: activeDays,
    );
  }

  static String dayKey(DateTime day) {
    final local = day.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final date = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$date';
  }

  static DateTime _day(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static int _currentStreak(Set<String> activeDays, DateTime today) {
    var cursor = today;
    if (!activeDays.contains(dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!activeDays.contains(dayKey(cursor))) return 0;
    }

    var count = 0;
    while (activeDays.contains(dayKey(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  static int _longestStreak(Set<String> activeDays) {
    if (activeDays.isEmpty) return 0;
    final dates = activeDays.map(_parseDayKey).toList()..sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < dates.length; i++) {
      if (dates[i].difference(dates[i - 1]).inDays == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }
    return longest;
  }

  static DateTime _parseDayKey(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }
}
