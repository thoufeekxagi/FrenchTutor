import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  static const _debugKey = String.fromEnvironment('E2E_GEMINI_API_KEY');

  static Future<String> _debugMint(bool modern) async {
    final now = DateTime.now().toUtc();
    final response = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/${modern ? 'v1beta' : 'v1alpha'}/auth_tokens',
          ),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _debugKey,
          },
          body: jsonEncode({
            'uses': 1,
            'expireTime': now
                .add(const Duration(minutes: 30))
                .toIso8601String(),
            'newSessionExpireTime': now
                .add(const Duration(minutes: 1))
                .toIso8601String(),
            if (modern)
              'bidiGenerateContentSetup': {'model': 'models/gemini-3.8-live'},
          }),
        )
        .timeout(const Duration(seconds: 10));
    final name = (jsonDecode(response.body) as Map)['name']?.toString();
    if (name == null || name.isEmpty) {
      throw StateError('Debug token mint failed: ${response.statusCode}');
    }
    return name;
  }

  static Future<String> fetch({bool trial = false, bool modern = false}) async {
    if (kDebugMode && _debugKey.isNotEmpty) return _debugMint(modern);
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
