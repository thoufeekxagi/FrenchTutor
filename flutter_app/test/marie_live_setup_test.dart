import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/prompts/live_prompts.dart';
import 'package:french_tutor/services/gemini_live_service.dart';
import 'package:french_tutor/services/gemini_live_token_service.dart';

void main() {
  test('Gemini 3.8 tutor calls use v1beta; other calls retain v1alpha', () {
    final uri = GeminiLiveTokenService.socketUri('test+/token', modern: true);
    expect(uri.scheme, 'wss');
    expect(uri.host, 'generativelanguage.googleapis.com');
    expect(
      uri.path,
      contains('v1beta.GenerativeService.BidiGenerateContentConstrained'),
    );
    expect(uri.queryParameters['access_token'], 'test+/token');
    expect(
      GeminiLiveTokenService.socketUri('legacy').path,
      contains('v1alpha.GenerativeService.BidiGenerateContentConstrained'),
    );
  });
  test(
    'lesson coach uses Gemini Live with context room and short turn endpoint',
    () {
      final service = GeminiLiveService(
        apiKey: 'unit-test-only',
        sessionType: LiveSessionType.lessonCoach,
      );
      final setup = service.buildSetupBody('short tutor contract');
      final generation = setup['generationConfig'] as Map<String, dynamic>;
      final proactive = setup['proactivity'] as Map<String, dynamic>;
      final vad =
          (setup['realtimeInputConfig']
                  as Map<String, dynamic>)['automaticActivityDetection']
              as Map<String, dynamic>;
      expect(setup['model'], 'models/gemini-3.8-live');
      expect(generation['thinkingConfig'], isNull);
      expect(generation['maxOutputTokens'], 1000);
      expect(proactive['proactiveAudio'], isTrue);
      expect(vad['disabled'], isFalse);
      expect(vad['silenceDurationMs'], 850);
      final compression =
          setup['contextWindowCompression'] as Map<String, dynamic>;
      expect(compression['triggerTokens'], 4000);
      expect(
        (compression['slidingWindow'] as Map<String, dynamic>)['targetTokens'],
        2000,
      );
      expect(setup['inputAudioTranscription'], isNotNull);
      expect(setup['outputAudioTranscription'], isNotNull);
    },
  );

  test('other Live contracts stay on their existing model', () {
    final service = GeminiLiveService(
      apiKey: 'unit-test-only',
      sessionType: LiveSessionType.freeTalk,
    );
    final setup = service.buildSetupBody('existing contract');
    expect(setup['model'], 'models/gemini-3.1-flash-live-preview');
    expect(setup.containsKey('proactivity'), isFalse);
  });

  test(
    'Live Tutor uses Gemini 3.8 with a 2k answer ceiling and bounded history',
    () {
      final service = GeminiLiveService(
        apiKey: 'unit-test-only',
        sessionType: LiveSessionType.liveTutor,
        liveTutorMode: true,
      );
      final setup = service.buildSetupBody('tutor contract');
      expect(setup['model'], 'models/gemini-3.8-live');
      expect(
        (setup['proactivity'] as Map<String, dynamic>)['proactiveAudio'],
        isTrue,
      );
      final compression =
          setup['contextWindowCompression'] as Map<String, dynamic>;
      expect(compression['triggerTokens'], 4000);
      expect(
        (compression['slidingWindow'] as Map<String, dynamic>)['targetTokens'],
        2000,
      );
      final generation = setup['generationConfig'] as Map<String, dynamic>;
      expect(generation['maxOutputTokens'], 2000);
      expect(generation['thinkingConfig'], isNull);
      final vad =
          (setup['realtimeInputConfig']
                  as Map<String, dynamic>)['automaticActivityDetection']
              as Map<String, dynamic>;
      expect(vad['silenceDurationMs'], 900);
    },
  );

  test('3.8 combined audio and transcript event delivers every part once', () {
    final service = GeminiLiveService(
      apiKey: 'unit-test-only',
      sessionType: LiveSessionType.lessonCoach,
    );
    final audio = <List<int>>[];
    final tutor = <String>[];
    final learner = <String>[];
    var completed = 0;
    service.onAudioChunk = audio.add;
    service.onTutorTranscript = tutor.add;
    service.onUserTranscript = learner.add;
    service.onTurnComplete = () => completed++;
    service.receiveServerMessageForTest({
      'serverContent': {
        'inputTranscription': {'text': 'Plus lentement'},
        'outputTranscription': {'text': 'Bien sûr.'},
        'modelTurn': {
          'parts': [
            {
              'inlineData': {
                'data': base64Encode([1, 2]),
                'mimeType': 'audio/pcm;rate=24000',
              },
            },
            {
              'inlineData': {
                'data': base64Encode([3, 4]),
                'mimeType': 'audio/pcm;rate=24000',
              },
            },
          ],
        },
        'turnComplete': true,
      },
    });
    expect(audio, [
      [1, 2],
      [3, 4],
    ]);
    expect(tutor, ['Bien sûr.']);
    expect(learner, ['Plus lentement']);
    expect(completed, 1);
  });

  test('proactive silence produces no invented tutor line', () {
    final service = GeminiLiveService(
      apiKey: 'unit-test-only',
      sessionType: LiveSessionType.lessonCoach,
    );
    final tutor = <String>[];
    var completed = 0;
    service.onTutorTranscript = tutor.add;
    service.onTurnComplete = () => completed++;
    service.receiveServerMessageForTest({
      'serverContent': {'turnComplete': true},
    });
    expect(tutor, isEmpty);
    expect(completed, 1);
  });
}
