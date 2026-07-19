import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/api_keys.dart';

/// Cross-platform paywall/entitlement client (iOS StoreKit + Android Play
/// Billing via RevenueCat's SDK). Supabase remains the source of truth for
/// the invite-code bonus system (referral_service.dart) — this class only
/// ever talks about *paid subscription* entitlement, synced into Supabase's
/// `entitlements` table by the `revenuecat-webhook` edge function whenever a
/// purchase/renewal/cancellation happens, so `PilotAccessService` still only
/// has to read one place.
///
/// Inert until a real RevenueCat project exists: [isConfigured] is false and
/// every method below is a safe no-op until `REVENUECAT_IOS_KEY` /
/// `REVENUECAT_ANDROID_KEY` are supplied via --dart-define. Web billing is
/// deliberately not wired here yet — RevenueCat's Web Billing setup differs
/// enough (a Stripe-backed flow) that it needs its own pass once the mobile
/// side is live and validated.
class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService shared = RevenueCatService._();

  bool _initialized = false;

  bool get isConfigured =>
      !kIsWeb &&
      ((Platform.isIOS && ApiKeys.revenueCatIosKey.isNotEmpty) ||
          (Platform.isAndroid && ApiKeys.revenueCatAndroidKey.isNotEmpty));

  Future<void> configure({required String appUserId}) async {
    if (!isConfigured || _initialized) return;
    final apiKey = Platform.isIOS
        ? ApiKeys.revenueCatIosKey
        : ApiKeys.revenueCatAndroidKey;
    await Purchases.configure(
      PurchasesConfiguration(apiKey)..appUserID = appUserId,
    );
    _initialized = true;
  }

  Future<bool> hasActiveEntitlement(String entitlementId) async {
    if (!_initialized) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (_) {
      return false;
    }
  }

  Future<Offerings?> fetchOfferings() async {
    if (!_initialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  Future<bool> purchasePackage(Package package) async {
    if (!_initialized) return false;
    try {
      await Purchases.purchasePackage(package);
      return true;
    } catch (_) {
      return false;
    }
  }
}
