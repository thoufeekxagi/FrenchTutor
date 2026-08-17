import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles speaking allowance adjustments.
///
/// The launch build keeps only the normal allowance, plus the existing
/// one-hour daily support grant for learners who reach the voice limit.
class LearningAllowanceService {
  LearningAllowanceService._();
  static final LearningAllowanceService shared = LearningAllowanceService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Cached in memory so a live-call time-limit check never waits on a
  /// network request.
  int cachedBonusSecondsBalance = 0;

  Future<int> refreshBonusBalance() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return cachedBonusSecondsBalance;
      final row = await _client
          .from('profiles')
          .select('bonus_seconds_balance')
          .eq('id', userId)
          .maybeSingle();
      cachedBonusSecondsBalance = (row?['bonus_seconds_balance'] as int?) ?? 0;
      return cachedBonusSecondsBalance;
    } catch (_) {
      return cachedBonusSecondsBalance;
    }
  }

  /// Best-effort accounting after a live call uses allowance seconds.
  Future<void> consumeBonusSeconds(int seconds) async {
    if (seconds <= 0) return;
    try {
      final result = await _client.rpc(
        'consume_bonus_seconds',
        params: {'p_seconds': seconds},
      );
      if (result is int) cachedBonusSecondsBalance = result;
    } catch (_) {
      // The next balance refresh corrects any temporary network miss.
    }
  }

  /// Gives a premium learner one extra hour once per calendar day after the
  /// regular voice allowance is exhausted. The server enforces the limit.
  Future<bool> grantDailyExtraHour() async {
    try {
      final result = await _client.rpc('grant_daily_extra_hour');
      final map = result as Map<String, dynamic>;
      if (map['success'] == true) {
        await refreshBonusBalance();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
