import '../models/session.dart';
import '../models/profile.dart';

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

  /// The daily mission is the learner's bridge into the broader Path. New
  /// learners always get the same low-friction first step. After that, the
  /// order reflects the goal they chose during onboarding while completion
  /// remains backed by the same session records everywhere in the app.
  static List<String> missionOrderFor(
    Profile profile, {
    bool hasHistory = true,
  }) {
    if (!hasHistory) return categories;
    return switch (profile.goal) {
      'everyday' => const [
        'Speaking',
        'Roleplay',
        'Listening',
        'Vocabulary',
        'Grammar',
        'Writing',
      ],
      'tef_canada' => const [
        'Vocabulary',
        'Grammar',
        'Listening',
        'Writing',
        'Speaking',
        'Roleplay',
      ],
      _ => categories,
    };
  }

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
      // `.toLocal()` matters here: locally-written timestamps have no `Z`
      // and parse as local already, but sessions hydrated from the server
      // (see commit 03b882c) come back UTC-tagged — without normalizing,
      // those bucket by UTC calendar day while local ones bucket by local
      // day, so the same session can land on "yesterday" or "tomorrow"
      // depending on where it came from and skew which categories look done.
      final started = DateTime.tryParse(session.startedAt)?.toLocal();
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
  static String? nextCategory(Set<String> doneToday, {List<String>? order}) {
    for (final category in order ?? categories) {
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
