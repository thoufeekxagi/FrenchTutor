import '../models/session.dart';

/// The day's practice goal — not a game streak, a plain accountability
/// check: did the learner touch each of these 6 skills today? Backed
/// entirely by the `sessions` table every practice screen already writes
/// to (see `SessionRecorder`) — no separate mission/plan machinery, so it
/// updates the same whether a category was done via "Today's mission" or
/// by going straight into Practice/Labs.
class DailyGoalService {
  const DailyGoalService._();

  /// Fixed order — also the order "Today's mission" offers them in.
  static const categories = [
    'Vocabulary',
    'Grammar',
    'Listening',
    'Roleplay',
    'Writing',
    'Speaking',
  ];

  /// Maps a `Session.stage` (set by whichever screen called
  /// `SessionRecorder`) to one of [categories]. Null = doesn't count toward
  /// the daily goal (nothing today writes an uncounted stage, but a session
  /// with a stage this map doesn't recognize is safer to ignore than crash).
  static String? categoryFor(String? stage) => switch (stage) {
    'vocab' => 'Vocabulary',
    'grammar' => 'Grammar',
    'reading_listening' => 'Listening',
    'story' => 'Listening',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'speaking' => 'Speaking',
    _ => null,
  };

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Distinct categories touched on [day] (defaults to today).
  static Set<String> categoriesOn(List<Session> sessions, [DateTime? day]) {
    final key = _dateKey(day ?? DateTime.now());
    final done = <String>{};
    for (final session in sessions) {
      final started = DateTime.tryParse(session.startedAt);
      if (started == null || _dateKey(started) != key) continue;
      final category = categoryFor(session.stage);
      if (category != null) done.add(category);
    }
    return done;
  }

  static Set<String> categoriesToday(List<Session> sessions) =>
      categoriesOn(sessions, DateTime.now());

  /// The first category (in fixed order) not yet done today — what "Today's
  /// mission" should offer next. Null once all 6 are done.
  static String? nextCategory(Set<String> doneToday) {
    for (final category in categories) {
      if (!doneToday.contains(category)) return category;
    }
    return null;
  }

  /// Consecutive days, ending today (or yesterday if today isn't finished
  /// yet — an incomplete today shouldn't zero out the streak while the day
  /// is still in progress), where all 6 categories were touched.
  static int streak(List<Session> sessions) {
    var day = DateTime.now();
    if (categoriesOn(sessions, day).length < categories.length) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (categoriesOn(sessions, day).length >= categories.length) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
