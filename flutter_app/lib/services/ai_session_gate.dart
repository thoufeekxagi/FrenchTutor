import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/app_router.dart';
import '../screens/subscription/paywall_screen.dart';
import '../widgets/adaptive/adaptive.dart';
import 'auth_service.dart';
import 'pilot_access_service.dart';
import 'product_analytics.dart';
import 'referral_service.dart';

/// Hard gate in front of every live Gemini-voice entry point. Without this,
/// PilotAccessService's daily-minute tracking is purely cosmetic bookkeeping
/// (it only debits bonus minutes after a call ends and shows a "X min left"
/// label in Settings) — nothing actually stops a call from connecting once
/// the free/premium allowance is spent, and every connected second is real
/// Gemini Live API spend. Call this immediately before pushing SessionScreen,
/// and only proceed if it returns true.
///
/// Takes [PilotAccessService] directly (not `WidgetRef`) rather than reading
/// it internally, so this stays callable from any context that already has
/// the service in hand (`ref.read(pilotAccessServiceProvider)`), not just
/// `ConsumerWidget`s.
Future<bool> ensureAiSessionQuota(
  BuildContext context,
  PilotAccessService accessService,
) async {
  final access = accessService.snapshot();
  if (access.remainingSeconds > 0) return true;
  if (!context.mounted) return false;

  final isPremium =
      PilotAccessService.baseDailyLimitSeconds(access.entitlement) >=
      PilotAccessService.subscribedDailyLimitSeconds;
  await ProductAnalytics.capture(
    'voice_quota_hit',
    properties: {'tier': isPremium ? 'premium' : 'free'},
  );
  if (!context.mounted) return false;

  if (!isPremium) {
    final upgrade = await showPSConfirmDialog(
      context,
      title: 'Out of free minutes today',
      message:
          "You've used today's 30 free minutes of speaking practice with "
          'Marie. Upgrade to Premium for 2 hours a day, or come back '
          'tomorrow.',
      confirmLabel: 'Upgrade to Premium',
      cancelLabel: 'Not now',
    );
    if (!upgrade || !context.mounted) return false;
    final subscribed = await AppRouter.push<bool>(
      context,
      (_) => const PaywallScreen(),
      fullscreenDialog: true,
    );
    // Re-check rather than trust the pop value blindly — a subscribed learner
    // still starts at their fresh 2-hour allowance, so this is never false
    // for someone who really did just subscribe.
    return subscribed == true && accessService.snapshot().remainingSeconds > 0;
  }

  final askForMore = await showPSConfirmDialog(
    context,
    title: 'Daily voice limit reached',
    message:
        "You've used your 2 hours of premium speaking practice for today, "
        "it resets tomorrow. Want 1 more free hour right now?",
    confirmLabel: 'Get 1 more hour',
    cancelLabel: 'OK',
  );
  if (!askForMore || !context.mounted) return false;

  // Self-serve first — instant, no waiting on a reply. Only asked once per
  // calendar day (enforced server-side in grant_daily_extra_hour), so a
  // learner who's already used today's bonus hour falls back to email.
  final granted = await ReferralService.shared.grantDailyExtraHour();
  if (granted) {
    await ProductAnalytics.capture('extra_hour_granted');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You've got 1 more free hour today, go ahead."),
        ),
      );
    }
    return context.mounted && accessService.snapshot().remainingSeconds > 0;
  }

  if (context.mounted) {
    await _requestMoreQuota();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You've already used today's bonus hour. We've got your request "
            "for more and will follow up.",
          ),
        ),
      );
    }
  }
  return false;
}

/// Opens a pre-filled email to the same address already shown in Settings'
/// "Feedback" row — deliberately a mailto rather than a new Supabase table,
/// since (a) it needs zero new backend before shipping, and (b) it reaches
/// an inbox immediately instead of sitting in a local `operational_events`
/// row with no upload path wired up yet.
Future<void> _requestMoreQuota() async {
  final email = AuthService.shared.currentSession?.user.email ?? 'unknown';
  final uri = Uri(
    scheme: 'mailto',
    path: 'thoufeekbaber1@gmail.com',
    query:
        'subject=${Uri.encodeComponent('ParleSprint: requesting more voice minutes')}'
        '&body=${Uri.encodeComponent('Account: $email\n\nHi, I\'ve been hitting my daily 2-hour voice practice limit and would like more.\n')}',
  );
  try {
    await launchUrl(uri);
  } catch (_) {
    // Best-effort — if no mail client is configured, there's nothing more to
    // do here; the confirmation snackbar above already set expectations.
  }
}
