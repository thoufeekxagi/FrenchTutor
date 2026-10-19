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

  test('only Latin-script English or French passes the language guard', () {
    expect(
      TutorReplyGuard.hasUnsupportedScript('എനിക്ക് കോഡ് ഒന്നുമില്ല.'),
      isTrue,
    );
    expect(TutorReplyGuard.hasUnsupportedScript('Привет, как дела?'), isTrue);
    expect(TutorReplyGuard.hasUnsupportedScript('你好'), isTrue);
    expect(TutorReplyGuard.hasUnsupportedScript('أهلا'), isTrue);
    expect(
      TutorReplyGuard.hasUnsupportedScript(
        'Où sont les toilettes ? « Çà » — ok…',
      ),
      isFalse,
    );
    expect(
      TutorReplyGuard.hasUnsupportedScript('bon\u2019jour \u00e9\u00e8'),
      isFalse,
    );
  });

  test('Spanish, Italian, German, Portuguese and Dutch are refused', () {
    for (final t in [
      'Hola, ¿cómo estás? Muy bien, gracias.',
      'Gracias',
      'Ciao, come stai? Sto molto bene, grazie.',
      'Buongiorno, posso aiutare?',
      'Danke, ich verstehe das nicht.',
      'wieder wieder',
      'Obrigado, não entendo muito bem.',
      'Ik begrijp het niet, dank je.',
      'Puedo ayudar con el español si quieres.',
    ]) {
      expect(TutorReplyGuard.isUnsupportedLanguage(t), isTrue, reason: t);
    }
  });

  test('English and French (including mixed teaching lines) pass', () {
    for (final t in [
      'Bonjour means hello or good morning in French.',
      'On dit simplement "bonsoir" pour dire "good evening" en anglais.',
      'Où sont les toilettes ?',
      'What does bonjour mean?',
      'Say it slower, please.',
      'To say "good night," you say "bonne nuit."',
      'Merci beaucoup, au revoir !',
      'Bonjour.',
      'Raihan',
      'The capital of Canada is Ottawa.',
      'Comment dit-on où sont les toilettes en français ?',
    ]) {
      expect(TutorReplyGuard.isUnsupportedLanguage(t), isFalse, reason: t);
    }
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

  group('follow-up question guard', () {
    test('finds a trailing question after an answer', () {
      const text = 'That sounds fun! Do you play hockey yourself?';
      expect(
        TutorReplyGuard.followUpQuestionStart(text),
        text.indexOf('Do you'),
      );
    });
    test('catches a question that has only just started', () {
      const text = 'That sounds fun! Do you play';
      expect(
        TutorReplyGuard.followUpQuestionStart(text),
        text.indexOf('Do you'),
      );
    });
    test('a lone question starts at zero', () {
      expect(
        TutorReplyGuard.followUpQuestionStart('Quel film avez-vous vu ?'),
        0,
      );
    });
    test('plain answers are left alone', () {
      expect(
        TutorReplyGuard.followUpQuestionStart(
          '"Déménager" means to move house.',
        ),
        -1,
      );
      expect(
        TutorReplyGuard.followUpQuestionStart(
          'You are welcome. How kind of you.',
        ),
        greaterThan(0),
        reason: 'an opener-like sentence is treated as a question tail',
      );
    });
  });

  group('run-on guard', () {
    const long =
        'You can say it in many ways and there are lots of options to learn '
        'today so let us go through each one in order and then practise all of '
        'them again slowly so that you remember every single phrase well and '
        'can use them with confidence in any situation that you may meet.';
    test('a long reply to a simple message is cut at a sentence end', () {
      expect(
        TutorReplyGuard.shouldCutRunOn(long, learnerTranscript: 'I like pizza'),
        isTrue,
      );
    });
    test('a short reply is never cut', () {
      expect(
        TutorReplyGuard.shouldCutRunOn(
          'Bonjour ! Ça va très bien, merci.',
          learnerTranscript: 'Bonjour',
        ),
        isFalse,
      );
    });
    test('an explanation request allows a long answer', () {
      expect(
        TutorReplyGuard.shouldCutRunOn(
          long,
          learnerTranscript: 'Explain the difference between tu and vous',
        ),
        isFalse,
      );
    });
    test('a very long unfinished reply is cut even mid-sentence', () {
      final words = List.filled(80, 'word').join(' ');
      expect(
        TutorReplyGuard.shouldCutRunOn(words, learnerTranscript: 'hello'),
        isTrue,
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

    test('a Malayalam reply is never played', () {
      final s = make();
      final audio = <List<int>>[];
      s.onAudioChunk = audio.add;
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'എനിക്ക് കോഡ് ഒന്നുമില്ല'},
        },
      });
      s.receiveServerMessageForTest(_reply('എന്ത് കാര്യമാണ് നിങ്ങളെ'));
      expect(audio, isEmpty);
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

    test('a run-on reply stops playback and keeps the first sentences', () {
      final s = GeminiLiveService(
        apiKey: 'unit-test-only',
        sessionType: LiveSessionType.liveTutor,
        liveTutorMode: true,
      );
      final audio = <List<int>>[];
      final tutor = <String>[];
      final guarded = <String>[];
      s.onAudioChunk = audio.add;
      s.onTutorTranscript = tutor.add;
      s.onReplyGuarded = guarded.add;
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'I like pizza'},
        },
      });
      final sentence = List.filled(14, 'word').join(' ');
      s.receiveServerMessageForTest(
        _reply('$sentence. $sentence. $sentence. $sentence.', done: false),
      );
      s.receiveServerMessageForTest(_reply(' More and more words.'));
      expect(guarded, ['runon']);
      expect(audio, isEmpty);
      expect(tutor, hasLength(1));
      expect(tutor.single.contains('More and more'), isFalse);
    });

    test('a second question in a row is trimmed off, the first is kept', () {
      final s = GeminiLiveService(
        apiKey: 'unit-test-only',
        sessionType: LiveSessionType.liveTutor,
        liveTutorMode: true,
      );
      final tutor = <String>[];
      final guarded = <String>[];
      s.onTutorTranscript = tutor.add;
      s.onReplyGuarded = guarded.add;
      // Turn 1: a statement then a question. Allowed (first question).
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'I like pizza'},
        },
      });
      s.receiveServerMessageForTest(_reply('Nice choice! Do you cook it?'));
      expect(guarded, isEmpty);
      expect(tutor, ['Nice choice! Do you cook it?']);
      // Turn 2: another question is trimmed, the statement stays.
      s.receiveServerMessageForTest({
        'serverContent': {
          'inputTranscription': {'text': 'Yes I do'},
        },
      });
      s.receiveServerMessageForTest(
        _reply('That is great! What toppings do you use?'),
      );
      expect(guarded, ['question']);
      expect(tutor.last, 'That is great!');
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
