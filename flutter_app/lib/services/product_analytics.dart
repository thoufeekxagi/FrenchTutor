import 'package:posthog_flutter/posthog_flutter.dart';

import '../config/api_keys.dart';

/// Thin wrapper around PostHog event capture — every call site elsewhere in
/// the app just calls `ProductAnalytics.capture(...)` without needing to know
/// whether a PostHog project is even configured yet (same "empty key = inert
/// no-op" pattern as RevenueCatService.isConfigured and every other optional
/// integration in this app). This is product/usage analytics ONLY — crash
/// reporting is Sentry (main.dart), never mixed in here.
class ProductAnalytics {
  ProductAnalytics._();

  static bool get isConfigured => ApiKeys.posthogApiKey.isNotEmpty;

  static Future<void> capture(
    String eventName, {
    Map<String, Object>? properties,
  }) async {
    if (!isConfigured) return;
    try {
      await Posthog().capture(eventName: eventName, properties: properties);
    } catch (_) {
      // Best-effort — analytics must never break or slow down the feature
      // it's observing.
    }
  }
}
