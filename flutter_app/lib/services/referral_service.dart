import 'package:supabase_flutter/supabase_flutter.dart';

/// What happened after a redeem attempt — mirrors the error codes returned
/// by the `redeem_referral_code` Postgres function, so the UI can show a
/// specific message instead of a generic failure.
enum RedeemOutcome {
  success,
  alreadyRedeemed,
  deviceAlreadyUsed,
  invalidCode,
  cannotRedeemOwnCode,
  codeLimitReached,
  networkError,
}

class RedeemResult {
  const RedeemResult(this.outcome, {this.bonusMinutes});
  final RedeemOutcome outcome;
  final int? bonusMinutes;
}

/// The owner's view of their own code — same code forever (no expiry, no
/// need to ever generate a new one), just a running count of how many of
/// the 5 slots have been redeemed so far.
class ReferralStats {
  const ReferralStats({
    required this.code,
    required this.successfulRedemptions,
    required this.maxRedemptions,
  });

  final String code;
  final int successfulRedemptions;
  final int maxRedemptions;
}

/// Supabase is the single source of truth for referral codes and bonus
/// minutes — this class is a thin wrapper around three Postgres RPCs
/// (`get_or_create_referral_code`, `redeem_referral_code`,
/// `consume_bonus_seconds`), all of which run server-side under the
/// caller's own auth.uid() so a client can only ever affect its own account
/// (plus, for a successful redemption, the specific code owner it redeemed).
class ReferralService {
  ReferralService._();
  static final ReferralService shared = ReferralService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Cached in memory only — refreshed via [refreshBonusBalance]. Read
  /// synchronously by [PilotAccessService.snapshot] so a network call
  /// during a live call's time-limit check is never on the critical path.
  int cachedBonusSecondsBalance = 0;

  Future<String?> myReferralCode() async {
    try {
      final result = await _client.rpc('get_or_create_referral_code');
      return result as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the code (creating it on first call, same as [myReferralCode])
  /// plus how many of its 5 redemption slots are used so far.
  Future<ReferralStats?> myReferralStats() async {
    try {
      final code = await myReferralCode();
      if (code == null) return null;
      final row = await _client
          .from('referral_codes')
          .select('successful_redemptions, max_redemptions')
          .eq('code', code)
          .maybeSingle();
      if (row == null) return null;
      return ReferralStats(
        code: code,
        successfulRedemptions: row['successful_redemptions'] as int,
        maxRedemptions: row['max_redemptions'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  Future<RedeemResult> redeem(String code, {required String installationId}) async {
    try {
      final result = await _client.rpc(
        'redeem_referral_code',
        params: {'p_code': code, 'p_installation_id': installationId},
      );
      final map = result as Map<String, dynamic>;
      if (map['success'] == true) {
        await refreshBonusBalance();
        return RedeemResult(
          RedeemOutcome.success,
          bonusMinutes: map['bonus_minutes'] as int?,
        );
      }
      final outcome = switch (map['error']) {
        'already_redeemed' => RedeemOutcome.alreadyRedeemed,
        'device_already_used' => RedeemOutcome.deviceAlreadyUsed,
        'cannot_redeem_own_code' => RedeemOutcome.cannotRedeemOwnCode,
        'code_limit_reached' => RedeemOutcome.codeLimitReached,
        _ => RedeemOutcome.invalidCode,
      };
      return RedeemResult(outcome);
    } catch (_) {
      return const RedeemResult(RedeemOutcome.networkError);
    }
  }

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

  /// Best-effort, fire-and-forget: called after a call ends that dipped into
  /// bonus time. Failure just means the balance corrects itself next
  /// [refreshBonusBalance] — never worth blocking or erroring the UI over.
  Future<void> consumeBonusSeconds(int seconds) async {
    if (seconds <= 0) return;
    try {
      final result = await _client.rpc(
        'consume_bonus_seconds',
        params: {'p_seconds': seconds},
      );
      if (result is int) cachedBonusSecondsBalance = result;
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }
}
