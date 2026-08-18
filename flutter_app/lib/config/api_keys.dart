abstract final class ApiKeys {
  /// Kept as an empty compatibility value for older widget constructors.
  /// Gemini Live uses a short-lived Supabase-minted token; Gemini text and
  /// OpenRouter are called by authenticated Edge Functions. No provider
  /// credential is compiled into any Flutter build.
  @Deprecated('Provider credentials are server-side; do not use this value.')
  static const geminiKey = '';

  /// Supabase project URL and anon/publishable key. The anon key is DESIGNED
  /// to be public — it's meaningless without the Row Level Security policies
  /// that gate what it can actually read/write — so, unlike the Gemini/
  /// OpenRouter keys above, it is not a secret. It still travels via
  /// dart-define for consistency with the rest of this file and so switching
  /// Supabase projects (e.g. a staging project) never requires a code change.
  ///
  /// The production public configuration is also the compile-time fallback.
  /// This is intentional: Xcode's native Run/Archive path does not execute
  /// our local key script, and Supabase's publishable key is safe to ship in a
  /// public client. A supplied dart-define still wins, so CI and staging can
  /// select a different project without changing source.
  static const _productionSupabaseUrl =
      'https://oxfnrsjskdjbroekxdco.supabase.co';
  static const _productionSupabasePublishableKey =
      'sb_publishable_jdorszpxwu--tDeMKkaARw_pGHf01nn';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _productionSupabaseUrl,
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _productionSupabasePublishableKey,
  );

  /// Google Sign-In OAuth client IDs (from Google Cloud Console — see
  /// BUILD_FLUTTER_TO_IPHONE.md for the one-time setup checklist). Neither is
  /// a secret (OAuth client IDs are public identifiers, not credentials), but
  /// both travel via dart-define like everything else here. Google sign-in
  /// gracefully reports "not configured" (AuthService.isGoogleConfigured)
  /// rather than crashing when these are empty — e.g. before the Google Cloud
  /// setup step has been done yet.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// RevenueCat's public SDK keys (one per store — these are safe to embed,
  /// same category as the Supabase anon key above: meaningless without a
  /// RevenueCat project behind them). Empty until a RevenueCat account/project
  /// exists — RevenueCatService reports "not configured" rather than crashing
  /// when these are blank, same pattern as Google Sign-In above.
  static const revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );

  /// Sentry's project DSN — safe to embed like the keys above (it identifies
  /// where crash reports go, it isn't a credential that grants access to
  /// anything). Empty until a Sentry project exists; main.dart skips
  /// SentryFlutter.init entirely when blank, same "not configured" pattern.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// PostHog project API key and ingestion host (e.g.
  /// 'https://us.i.posthog.com' or 'https://eu.i.posthog.com', depending on
  /// which region the project was created in). Same "empty means not
  /// configured, skip setup entirely" pattern as every other optional key
  /// above — main.dart never calls Posthog().setup when this is blank.
  static const posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );
}
