import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/prompts/live_prompts.dart';
import 'package:french_tutor/services/gemini_live_service.dart';
import 'package:french_tutor/services/tutor_reply_guard.dart';

Map<String, dynamic> _reply(String text, {String? heard, bool done = true}) => {
  'serverContent': {
    if (heard != null) 'inputTranscription': {'text': heard},
    'outputTranscription': {'text': text},
    'modelTurn': {
      'parts': [
        {
          'inlineData': {
            'data': base64Encode([1, 2]),
            'mimeType': 'audio/pcm;rate=24000',
          },
        },
      ],
    },
    if (done) 'turnComplete': true,
  },
};

void main() {
  group('TutorReplyGuard.isFillerTurn', () {
    test('fillers, thanks and acknowledgements are not requests', () {
      for (final t in [
        'Hmm... uh... okay.',
        'Ham, uh, okay.',
        "Okay, thanks Marie. That's all.",
        'Okay, okay, got it. Thanks.',
        'Oui, merci.',
        'Euh... ok.',
        'Yeah right',
      ]) {
        expect(TutorReplyGuard.isFillerTurn(t), isTrue, reason: t);
      }
    });
    test('real requests and attempts are never filler', () {
      for (final t in [
        'What does bonjour mean?',
        'Say it slower',
        'Bonjour.',
        'Why is there an n?',
        'Okay but what does it mean?',
        'How do I spell bonjour?',
        '',
      ]) {
        expect(TutorReplyGuard.isFillerTurn(t), isFalse, reason: t);
      }
    });
  });

  group('TutorReplyGuard.chatterStart', () {
    test('finds generic offers and ignores teaching', () {
      expect(
        TutorReplyGuard.chatterStart(
          'It means hello. Let me know if you need anything else.',
        ),
        greaterThan(0),
      );
      expect(
        TutorReplyGuard.chatterStart("Bonjour ! Comment puis-je vous aider ?"),
        greaterThan(0),
      );
      expect(
        TutorReplyGuard.chatterStart('Bonjour means hello or good day.'),
        -1,
      );
    });
  });

  group('GeminiLiveService reply guard', () {
    GeminiLiveService make() => GeminiLiveService(
      apiKey: 'unit-test-only',
      sessionType: LiveSessionType.lessonCoach,
    );

    test('a reply to a filler never reaches playback or the transcript', () {
      final s = make();
      final audio = <List<int>>[];
      final tutor = <String>[];
      final guarded = <String>[];
      s.onAudioChunk = audio.add;
      s.onTutorTranscript = tutor.add;
      s.onReplyGuarded = guarded.add;
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'Hmm, uh, okay.'},
        },
      });
      s.receiveServerMessageForTest(_reply('Do you have any questions?'));
      expect(audio, isEmpty);
      expect(tutor, isEmpty);
      expect(guarded, ['filler']);
    });

    test('a real question is answered normally', () {
      final s = make();
      final audio = <List<int>>[];
      final tutor = <String>[];
      s.onAudioChunk = audio.add;
      s.onTutorTranscript = tutor.add;
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'What does bonjour mean?'},
        },
      });
      s.receiveServerMessageForTest(_reply('It means hello.'));
      expect(audio, hasLength(1));
      expect(tutor, ['It means hello.']);
    });

    test('a chatbot tail is cut and not surfaced', () {
      final s = make();
      final audio = <List<int>>[];
      final tutor = <String>[];
      final guarded = <String>[];
      s.onAudioChunk = audio.add;
      s.onTutorTranscript = tutor.add;
      s.onReplyGuarded = guarded.add;
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'Say it slower'},
        },
      });
      s.receiveServerMessageForTest(_reply('Bon... jour.', done: false));
      s.receiveServerMessageForTest(
        _reply(' Let me know if you need anything else.'),
      );
      expect(audio, hasLength(1));
      expect(guarded, ['chatter']);
      expect(tutor.join(' ').contains('Let me know'), isFalse);
    });
  });
}
