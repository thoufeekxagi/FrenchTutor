import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:french_tutor/data/alphabet_data.dart';
import 'package:french_tutor/services/lesson_agent_service.dart';
import 'package:french_tutor/models/tutor_persona.dart';

void main() {
  test('builds a French catalog for every voice and alphabet item', () {
    final items = alphabetPrewarmItems();

    expect(items, hasLength(TutorPersona.all.length * 31));
    expect(
      items.where((item) => item.text == 'ku'),
      hasLength(TutorPersona.all.length),
    );
    expect(
      items.every(
        (item) =>
            item.language == 'fr-FR' &&
            item.voiceName != null &&
            item.assetPath!.startsWith('assets/audio/alphabet/'),
      ),
      isTrue,
    );
  });

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

  test('keeps OpenRouter failures distinguishable from Gemini failures', () {
    final error = AiProviderHttpError(
      'openrouter',
      400,
      message: 'invalid response format',
    );

    expect(
      error.toString(),
      'OpenRouterHttpError(400): invalid response format',
    );
    expect(error.isRateLimited, isFalse);
  });

  test('warm-up request keeps only three future lessons and stays bounded', () {
    final huge = List.filled(20000, 'x').join();
    final message = LessonAgentService.buildBoundedReviewMessageForTest({
      'version': 1,
      'request': {
        'kind': 'warmup',
        'localSuggestedMode': 'smart',
        'primaryTopic': 'Upcoming course work',
        'futureSessionIds': List.generate(8, (index) => 'future-$index'),
        'futureLessonSummaries': List.generate(
          8,
          (index) => 'Lesson $index $huge',
        ),
        'futureCourseContext': huge,
      },
      'recentSessions': List.generate(
        20,
        (index) => {
          'id': 'recent-$index',
          'source': index == 0 ? 'course' : 'practice',
          'summary': huge,
        },
      ),
      'vocabularyEvidence': List.generate(20, (_) => huge),
      'recentLearnerTranscriptExcerpts': List.generate(20, (_) => huge),
      'performanceSignals': List.generate(20, (_) => huge),
    });

    expect(message.length, lessThanOrEqualTo(6000));
    final dossier = jsonDecode(message.split('\n').skip(1).join('\n')) as Map;
    final request = dossier['request'] as Map;
    expect(request['kind'], 'warmup');
    expect(request['futureSessionIds'], isEmpty);
    expect(request['futureLessonSummaries'], isEmpty);
    expect(request['futureCourseContext'], isNull);
    final evidence = dossier['recentSessions'] as List;
    expect(evidence, hasLength(4));
    expect((evidence.first as Map)['source'], 'course');
    expect((evidence[1] as Map)['source'], 'upcoming_course');
    expect(dossier['vocabularyEvidence'], isEmpty);
    expect(dossier['recentLearnerTranscriptExcerpts'], isEmpty);
    expect(dossier['performanceSignals'], isEmpty);
  });
}
