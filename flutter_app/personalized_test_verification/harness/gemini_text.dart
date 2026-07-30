import 'dart:convert';
import 'package:http/http.dart' as http;

/// Minimal direct-HTTP Gemini text client — mirrors the pattern already used
/// by tool/generate_mission_bank.dart (no SDK, raw JSON navigation, same
/// extractJSON markdown-fence stripping as LessonAgentService). Shared by
/// the synthetic-learner submission generator and the verify_journey judge —
/// neither of those is production app code, so they don't reuse
/// LessonAgentService itself, only its calling convention.
class GeminiTextClient {
  GeminiTextClient({required this.apiKey, this.model = 'gemini-2.5-flash-lite'});

  final String apiKey;
  final String model;

  int callCount = 0;
  int errorCount = 0;

  Future<String> generate(String prompt, {int maxRetries = 3}) async {
    callCount++;
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt},
                    ],
                  },
                ],
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 429 || response.statusCode >= 500) {
          lastError = Exception('HTTP ${response.statusCode}: ${response.body}');
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        if (response.statusCode < 200 || response.statusCode > 299) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No candidates in response: ${response.body}');
        }
        final content = (candidates.first as Map<String, dynamic>)['content']
            as Map<String, dynamic>?;
        final parts = (content?['parts'] as List?) ?? const [];
        return parts
            .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
            .join();
      } catch (e) {
        lastError = e;
        errorCount++;
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }
    throw Exception('Gemini call failed after $maxRetries retries: $lastError');
  }

  /// Mirrors LessonAgentService.extractJSON — strips markdown code fences
  /// the model sometimes wraps its JSON in despite being told not to.
  static String extractJSON(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final firstNewline = s.indexOf('\n');
      if (firstNewline != -1) s = s.substring(firstNewline + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    return s.trim();
  }
}
