import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_router.dart';
import '../../providers/database_provider.dart';
import '../../screens/subscription/speak_paywall_screen.dart';
import '../../services/revenue_cat_service.dart';
import '../lesson/v3_lesson.dart';
import '../v3_cloud_state.dart';
import '../v3_prefs.dart';

enum V3PracticeKind { marie, stories }

/// What is free before the App Store subscription, in one place.
///
/// - Stage 0 and the dev sample are always free.
/// - The first 7 lessons of each of A1, A2, B1 and B2 are free.
/// - The first 7 daily challenges are free.
/// - 7 Talk with Marie sessions and 7 stories are free. Review words is free.
/// - Tests are free for the first 7 days.
///
/// A subscriber (or a debug override) is never limited. The counters are saved
/// on the phone and in the learner's account, so a reinstall cannot reset them.
abstract final class V3Access {
  static const freeLessonsPerLevel = 7;
  static const freeDailyChallenges = 7;
  static const freePracticeUses = 7;
  static const freeExamDays = 7;

  static const _levels = {'a1', 'a2', 'b1', 'b2'};

  static String _level(String lessonId) => lessonId.split('-').first;

  /// Position of [lesson] among the lessons of its own level in [all].
  static int indexInLevel(V3Lesson lesson, List<V3Lesson> all) {
    final level = _level(lesson.id);
    final inLevel = all.where((l) => _level(l.id) == level).toList();
    final i = inLevel.indexWhere((l) => l.id == lesson.id);
    return i < 0 ? 0 : i;
  }

  static bool lessonLocked({
    required String lessonId,
    required int indexInLevel,
    required bool premium,
  }) {
    if (premium) return false;
    if (!_levels.contains(_level(lessonId))) return false;
    return indexInLevel >= freeLessonsPerLevel;
  }

  static bool dailyChallengeLocked({
    required Set<String> usedDays,
    required String today,
    required bool premium,
  }) =>
      !premium &&
      !usedDays.contains(today) &&
      usedDays.length >= freeDailyChallenges;

  static bool practiceLocked({required int uses, required bool premium}) =>
      !premium && uses >= freePracticeUses;

  static int examDaysUsed(DateTime startedOn, DateTime now) => DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(startedOn.year, startedOn.month, startedOn.day)).inDays;

  static bool examLocked({
    required DateTime startedOn,
    required DateTime now,
    required bool premium,
  }) => !premium && examDaysUsed(startedOn, now) >= freeExamDays;

  static int examDaysLeft(DateTime startedOn, DateTime now) =>
      (freeExamDays - examDaysUsed(startedOn, now)).clamp(0, freeExamDays);

  static bool premium(WidgetRef ref) =>
      ref.read(subscriptionGateServiceProvider).hasPremiumAccess;

  /// Shows the App Store subscription screen. Returns true when the learner
  /// is subscribed afterwards.
  static Future<bool> openPaywall(
    BuildContext context,
    WidgetRef ref, {
    required String source,
  }) async {
    await AppRouter.push<void>(
      context,
      (_) => SpeakPaywallScreen(source: source),
      fullscreenDialog: true,
    );
    await RevenueCatService.shared.refreshCustomerInfo();
    return premium(ref);
  }
}

/// Saved free-allowance counters (phone and account).
abstract final class V3FreeUsage {
  static String get _startKey => v3Key('v3_free_started_on');
  static String get _daysKey => v3Key('v3_free_daily_days');
  static String _usesKey(V3PracticeKind k) => v3Key('v3_free_uses_${k.name}');

  static String dateKey([DateTime? value]) {
    final d = (value ?? DateTime.now()).toLocal();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// The day the learner first opened the course. Set once, kept forever.
  static Future<DateTime> startedOn() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = DateTime.tryParse(prefs.getString(_startKey) ?? '');
    if (saved != null) return saved;
    final today = dateKey();
    await prefs.setString(_startKey, today);
    V3CloudState.push('v3_free_started_on');
    return DateTime.parse(today);
  }

  static Future<Set<String>> dailyDays() async =>
      ((await SharedPreferences.getInstance()).getStringList(_daysKey) ??
              const [])
          .toSet();

  static Future<void> recordDaily([String? day]) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_daysKey) ?? const []).toSet()
      ..add(day ?? dateKey());
    await prefs.setStringList(_daysKey, set.toList());
    V3CloudState.push('v3_free_daily_days');
  }

  static Future<int> uses(V3PracticeKind kind) async =>
      (await SharedPreferences.getInstance()).getInt(_usesKey(kind)) ?? 0;

  static Future<void> recordUse(V3PracticeKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_usesKey(kind), (prefs.getInt(_usesKey(kind)) ?? 0) + 1);
    V3CloudState.push('v3_free_uses_${kind.name}');
  }
}
