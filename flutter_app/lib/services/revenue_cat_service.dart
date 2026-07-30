import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
    if (_initialized) return;
    if (!isConfigured) {
      debugPrint(
        'RevenueCatService: not configured — no API key for this platform '
        '(pass --dart-define=REVENUECAT_IOS_KEY=... / '
        '--dart-define=REVENUECAT_ANDROID_KEY=...). The paywall will show '
        'zero packages until this is set.',
      );
      return;
    }
    final apiKey = Platform.isIOS
        ? ApiKeys.revenueCatIosKey
        : ApiKeys.revenueCatAndroidKey;
    try {
      await Purchases.configure(
        PurchasesConfiguration(apiKey)..appUserID = appUserId,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('RevenueCatService: Purchases.configure failed — $e');
    }
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

  /// The full active entitlement record (product id + expiration), so a
  /// caller can show a real "renews on / days left" right after purchase
  /// instead of waiting on the revenuecat-webhook -> Supabase sync round-trip.
  Future<EntitlementInfo?> activeEntitlementInfo(String entitlementId) async {
    if (!_initialized) return null;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active[entitlementId];
    } catch (_) {
      return null;
    }
  }

  Future<Offerings?> fetchOfferings() async {
    if (!_initialized) {
      debugPrint(
        'RevenueCatService.fetchOfferings: SDK not initialized (configure() '
        'never succeeded) — returning null, paywall will show no packages.',
      );
      return null;
    }
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current == null) {
        debugPrint(
          'RevenueCatService.fetchOfferings: got a response but there is no '
          '"current" offering — check the Offerings config in the '
          'RevenueCat dashboard.',
        );
      } else if (offerings.current!.availablePackages.isEmpty) {
        debugPrint(
          'RevenueCatService.fetchOfferings: current offering '
          '"${offerings.current!.identifier}" has zero packages attached — '
          'check that its products are attached in the RevenueCat dashboard '
          'and that they\'re in an approved/ready state in App Store Connect.',
        );
      }
      return offerings;
    } catch (e) {
      debugPrint('RevenueCatService.fetchOfferings failed — $e');
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
