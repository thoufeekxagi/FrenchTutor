import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors the error codes returned by the `redeem_subscription_invite_code`
/// Postgres function (see supabase/migrations/20260720000000_subscription_invite_codes.sql).
enum InviteRedeemOutcome {
  success,
  alreadyRedeemed,
  invalidCode,
  codeInactive,
  codeLimitReached,
  networkError,
}

class InviteRedeemResult {
  const InviteRedeemResult(this.outcome, {this.monthsGranted, this.expiresAt});
  final InviteRedeemOutcome outcome;
  final int? monthsGranted;
  final DateTime? expiresAt;
}

/// Distinct from ReferralService (which only grants bonus speaking minutes) —
/// this redeems an admin-issued code for a real subscription period, mirroring
/// the same purchase entitlement that RevenueCat grants (see profiles.subscription_active).
class SubscriptionInviteService {
  SubscriptionInviteService._();
  static final SubscriptionInviteService shared = SubscriptionInviteService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<InviteRedeemResult> redeem(String code) async {
    try {
      final result = await _client.rpc(
        'redeem_subscription_invite_code',
        params: {'p_code': code},
      );
      final map = result as Map<String, dynamic>;
      if (map['success'] == true) {
        final expiresAtRaw = map['expires_at'] as String?;
        return InviteRedeemResult(
          InviteRedeemOutcome.success,
          monthsGranted: map['months_granted'] as int?,
          expiresAt: expiresAtRaw != null ? DateTime.tryParse(expiresAtRaw) : null,
        );
      }
      final outcome = switch (map['error']) {
        'already_redeemed' => InviteRedeemOutcome.alreadyRedeemed,
        'code_inactive' => InviteRedeemOutcome.codeInactive,
        'code_limit_reached' => InviteRedeemOutcome.codeLimitReached,
        _ => InviteRedeemOutcome.invalidCode,
      };
      return InviteRedeemResult(outcome);
    } catch (_) {
      return const InviteRedeemResult(InviteRedeemOutcome.networkError);
    }
  }
}
