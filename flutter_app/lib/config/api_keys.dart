abstract final class ApiKeys {
  static const geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const openRouterKey = String.fromEnvironment('OPENROUTER_API_KEY');

  /// Supabase project URL and anon/publishable key. The anon key is DESIGNED
  /// to be public — it's meaningless without the Row Level Security policies
  /// that gate what it can actually read/write — so, unlike the Gemini/
  /// OpenRouter keys above, it is not a secret. It still travels via
  /// dart-define for consistency with the rest of this file and so switching
  /// Supabase projects (e.g. a staging project) never requires a code change.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Google Sign-In OAuth client IDs (from Google Cloud Console — see
  /// BUILD_FLUTTER_TO_IPHONE.md for the one-time setup checklist). Neither is
  /// a secret (OAuth client IDs are public identifiers, not credentials), but
  /// both travel via dart-define like everything else here. Google sign-in
  /// gracefully reports "not configured" (AuthService.isGoogleConfigured)
  /// rather than crashing when these are empty — e.g. before the Google Cloud
  /// setup step has been done yet.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// RevenueCat's public SDK keys (one per store — these are safe to embed,
  /// same category as the Supabase anon key above: meaningless without a
  /// RevenueCat project behind them). Empty until a RevenueCat account/project
  /// exists — RevenueCatService reports "not configured" rather than crashing
  /// when these are blank, same pattern as Google Sign-In above.
  static const revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );
}
