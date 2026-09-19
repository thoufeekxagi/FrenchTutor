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

/// Enforces the Course-specific free boundary without consuming the shared
/// daily preview. Units 1–2 are always accessible; Unit 3+ only opens after a
/// verified subscription purchase or restore.
Future<bool> requireCourseUnitAccess(
  BuildContext context,
  WidgetRef ref,
  int unit, {
  String source = 'course',
}) async {
  final gate = ref.read(subscriptionGateServiceProvider);
  if (!gate.isCourseUnitLocked(unit)) return true;

  if (!context.mounted) return false;
  final purchased = await AppRouter.push<bool>(
    context,
    (_) => SpeakPaywallScreen(source: source),
    fullscreenDialog: true,
  );
  if (!context.mounted || purchased != true) return false;
  // A dismissed paywall or an unverified purchase must never open the row.
  return !ref.read(subscriptionGateServiceProvider).isCourseUnitLocked(unit);
}
