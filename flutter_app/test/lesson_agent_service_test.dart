import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:french_tutor/services/lesson_agent_service.dart';

void main() {
  test('reads Gemini retry delay from a quota response', () {
    final error = GeminiHttpError.fromResponse(
      http.Response(
        '{"error":{"message":"Quota exceeded. Please retry in 36.886s."}}',
        429,
      ),
    );

    expect(error.isRateLimited, isTrue);
    expect(error.retryAfter, const Duration(milliseconds: 37386));
  });

  test('leaves retry delay unset when Gemini does not provide one', () {
    final error = GeminiHttpError.fromResponse(
      http.Response('{"error":{"message":"Forbidden"}}', 403),
    );

    expect(error.isRateLimited, isFalse);
    expect(error.retryAfter, isNull);
  });
}
