import 'package:supabase_flutter/supabase_flutter.dart';

/// Mints a short-lived Gemini Live credential through the authenticated
/// Supabase Edge Function. The long-lived Gemini API key never enters the app.
class GeminiLiveTokenService {
  GeminiLiveTokenService._();

  /// Gemini 3.8 tutor calls use the v1beta ephemeral-token endpoint. Existing
  /// non-tutor Live surfaces retain their deployed v1alpha token function and
  /// socket.
  static Uri socketUri(String token, {bool modern = false}) => Uri.parse(
    'wss://generativelanguage.googleapis.com/ws/'
    'google.ai.generativelanguage.${modern ? 'v1beta' : 'v1alpha'}.GenerativeService.'
    'BidiGenerateContentConstrained?access_token=${Uri.encodeQueryComponent(token)}',
  );

  static Future<String> fetch({bool trial = false, bool modern = false}) async {
    if (!trial && Supabase.instance.client.auth.currentSession == null) {
      throw StateError('A signed-in session is required for Gemini Live');
    }
    final response = await Supabase.instance.client.functions
        .invoke(
          trial
              ? 'gemini-live-trial-token'
              : modern
              ? 'gemini-live-v3-token'
              : 'gemini-live-token',
        )
        .timeout(const Duration(seconds: 10));
    final data = response.data;
    final token = data is Map ? data['token']?.toString() : null;
    if (token == null || token.isEmpty) {
      throw StateError('Gemini Live token was not returned');
    }
    return token;
  }
}
