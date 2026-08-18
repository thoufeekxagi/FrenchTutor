import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/api_keys.dart';

/// Cross-platform paywall/entitlement client (iOS StoreKit + Android Play
/// Billing via RevenueCat's SDK). Apple/Google store transactions are the
/// billing authority; RevenueCat is the entitlement adapter and cache. The
/// app persists the resulting entitlement locally so route gates can remain
/// synchronous and offline-safe.
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
  String? _appUserId;
  CustomerInfoUpdateListener? _customerInfoListener;
  bool _listenerRegistered = false;

  bool get isConfigured =>
      !kIsWeb &&
      ((Platform.isIOS && ApiKeys.revenueCatIosKey.isNotEmpty) ||
          (Platform.isAndroid && ApiKeys.revenueCatAndroidKey.isNotEmpty));

  Future<void> configure({
    required String appUserId,
    CustomerInfoUpdateListener? onCustomerInfo,
  }) async {
    _customerInfoListener ??= onCustomerInfo;
    if (!isConfigured) {
      debugPrint(
        'RevenueCatService: not configured — no API key for this platform '
        '(pass --dart-define=REVENUECAT_IOS_KEY=... / '
        '--dart-define=REVENUECAT_ANDROID_KEY=...). The paywall will show '
        'zero packages until this is set.',
      );
      return;
    }
    if (_initialized) {
      _registerCustomerInfoListener();
      if (_appUserId != appUserId) {
        try {
          final result = await Purchases.logIn(appUserId);
          _appUserId = appUserId;
          _customerInfoListener?.call(result.customerInfo);
        } catch (e) {
          debugPrint('RevenueCatService.logIn failed — $e');
        }
      } else {
        await refreshCustomerInfo();
      }
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
      _appUserId = appUserId;
      _registerCustomerInfoListener();
      await refreshCustomerInfo();
    } catch (e) {
      debugPrint('RevenueCatService: Purchases.configure failed — $e');
    }
  }

  void _registerCustomerInfoListener() {
    if (_listenerRegistered || _customerInfoListener == null) return;
    Purchases.addCustomerInfoUpdateListener(_customerInfoListener!);
    _listenerRegistered = true;
  }

  Future<CustomerInfo?> refreshCustomerInfo() async {
    if (!_initialized) return null;
    try {
      final info = await Purchases.getCustomerInfo();
      _customerInfoListener?.call(info);
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<void> logOut() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
    } catch (_) {
      // RevenueCat can already be anonymous after a partial sign-out. The
      // app's Supabase auth state remains the owner of session navigation.
    }
    _appUserId = null;
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
  /// instead of waiting for a later app refresh.
  Future<EntitlementInfo?> activeEntitlementInfo(String entitlementId) async {
    final info = await refreshCustomerInfo();
    return info?.entitlements.active[entitlementId];
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

  /// Purchases the package and immediately forwards RevenueCat's returned
  /// customer snapshot to the same listener used for restores and renewals.
  ///
  /// The SDK returns the post-purchase [CustomerInfo] directly. Waiting only
  /// for the asynchronous listener is racy: the transaction can succeed,
  /// while the paywall still has no cached entitlement for one frame (or
  /// longer on a slow sandbox device).
  Future<CustomerInfo?> purchasePackage(Package package) async {
    if (!_initialized) return null;
    try {
      final info = await Purchases.purchasePackage(package);
      _customerInfoListener?.call(info);
      return info;
    } catch (_) {
      return null;
    }
  }
}
