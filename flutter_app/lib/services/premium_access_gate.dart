import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_router.dart';
import '../providers/database_provider.dart';
import '../screens/subscription/speak_paywall_screen.dart';
import 'subscription_gate_service.dart';

/// One UI entry point for every premium area. A free learner gets one
/// meaningful premium session per local day; a paid learner gets everything.
/// The result is re-checked after the paywall rather than trusting navigation.
Future<bool> requirePremiumArea(
  BuildContext context,
  WidgetRef ref,
  PremiumArea area, {
  String source = 'unknown',
}) async {
  final gate = ref.read(subscriptionGateServiceProvider);
  if (gate.tryEnter(area)) {
    ref.invalidate(subscriptionGateServiceProvider);
    return true;
  }

  if (!context.mounted) return false;
  final purchased = await AppRouter.push<bool>(
    context,
    (_) => SpeakPaywallScreen(source: source),
    fullscreenDialog: true,
  );
  if (!context.mounted || purchased != true) return false;
  return ref.read(subscriptionGateServiceProvider).hasPremiumAccess;
}
