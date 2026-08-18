import 'package:supabase_flutter/supabase_flutter.dart';

/// Mints a short-lived Gemini Live credential through the authenticated
/// Supabase Edge Function. The long-lived Gemini API key never enters the app.
class GeminiLiveTokenService {
  GeminiLiveTokenService._();

  static Future<String> fetch() async {
    if (Supabase.instance.client.auth.currentSession == null) {
      throw StateError('A signed-in session is required for Gemini Live');
    }
    final response = await Supabase.instance.client.functions
        .invoke('gemini-live-token')
        .timeout(const Duration(seconds: 10));
    final data = response.data;
    final token = data is Map ? data['token']?.toString() : null;
    if (token == null || token.isEmpty) {
      throw StateError('Gemini Live token was not returned');
    }
    return token;
  }
}
