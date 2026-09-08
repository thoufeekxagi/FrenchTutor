import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/services/course_artifact_codec.dart';

Map<String, dynamic> storyArtifact({String? audioPath}) => {
  'id': 'story-1',
  'levelBand': 'A1',
  'createdAt': '2026-09-05T00:00:00Z',
  'passage': {
    'id': 'passage-1',
    'title': 'Une petite histoire',
    'titleEn': 'A short story',
    'segments': [
      {
        'fr': 'Lina ouvre la porte.',
        'en': 'Lina opens the door.',
        'grammarNote': '',
        'pronunciationTip': '',
      },
      {
        'fr': 'Elle trouve une lettre.',
        'en': 'She finds a letter.',
        'grammarNote': '',
        'pronunciationTip': '',
      },
      {
        'fr': 'Elle sourit.',
        'en': 'She smiles.',
        'grammarNote': '',
        'pronunciationTip': '',
      },
    ],
    'fullText': 'Lina ouvre la porte. Elle trouve une lettre. Elle sourit.',
  },
  'quiz': [
    {
      'q': 'Que trouve Lina ?',
      'choices': ['Une lettre', 'Un livre', 'Une clé'],
      'answerIndex': 0,
    },
  ],
  'keywords': <Map<String, dynamic>>[],
  if (audioPath != null) 'audioPath': audioPath,
  if (audioPath != null) 'audioMode': 'educational',
};

void main() {
  test('reading decodes a complete persisted story', () {
    final story = CourseArtifactCodec.story(storyArtifact());
    expect(story.passage.segments, hasLength(3));
    expect(story.quiz, hasLength(1));
  });

  test('course listening refuses to synthesize missing audio', () {
    expect(
      () => CourseArtifactCodec.listening(storyArtifact()),
      throwsFormatException,
    );
    final listening = CourseArtifactCodec.listening(
      storyArtifact(audioPath: 'user/course/listening.mp3'),
    );
    expect(listening.audioPath, 'user/course/listening.mp3');
    expect(listening.practiceMode, 'listening');
  });

  test('legacy Unit 2 marker resolves to the shared listening asset', () {
    final listening = CourseArtifactCodec.listening({
      ...storyArtifact(audioPath: 'pcm-deck-v1:unit-two-listening'),
      'id': 'unit-two-listening',
    });
    expect(listening.audioPath, 'course-shared/unit-two-listening.wav');
    expect(listening.audioMode, 'gemini_flash_tts');
  });

  test('writing decodes one prepared task', () {
    final writing = CourseArtifactCodec.writing({
      'createdAt': '2026-09-05T00:00:00Z',
      'task': {
        'id': 'writing-1',
        'type': 'guided',
        'title': 'Un message',
        'titleEn': 'A message',
        'promptFr': 'Écrivez un message court.',
        'promptEn': 'Write a short message.',
        'minWords': 30,
        'targetConnectors': ['et'],
        'rubricHints': ['State the purpose.'],
        'levelBand': 'A1',
      },
    });
    expect(writing.task.id, 'writing-1');
  });

  test('course writing enters the exact native Writing mode', () {
    final lesson = CourseArtifactCodec.writingCourse({
      'practiceMode': 'guided',
      'lesson': {
        'id': 'writing-course-1',
        'title': 'Dire bonjour',
        'subtitle': 'Build one short greeting.',
        'level': 'A1',
        'mode': 'guided',
        'goal': 'Write a greeting.',
        'steps': List.generate(
          5,
          (index) => {
            'prompt': 'Écris la phrase.',
            'prompt_english': 'Write the sentence.',
            'target': 'Bonjour Marie.',
            'kind': 'arrange',
            'tokens': ['Bonjour', 'Marie.'],
            'token_meanings': ['Hello', 'Marie'],
            'tip': 'Start with hello.',
          },
        ),
      },
    });
    expect(lesson.mode.name, 'guided');
    expect(lesson.steps, hasLength(5));
    expect(lesson.steps.every((step) => step.kind.name == 'arrange'), isTrue);
  });

  test('guided writing keeps punctuation out of selectable word chips', () {
    final lesson = CourseArtifactCodec.writingCourse({
      'practiceMode': 'guided',
      'lesson': {
        'id': 'writing-punctuation-1',
        'title': 'Dire bonjour',
        'subtitle': 'Build five short greetings.',
        'level': 'A1',
        'mode': 'guided',
        'goal': 'Write a greeting.',
        'steps': List.generate(
          5,
          (index) => {
            'prompt': 'Écris la phrase.',
            'prompt_english': 'Write the sentence.',
            'target': 'Bonjour Marie.',
            'kind': 'arrange',
            'tokens': ['Bonjour', 'Marie.', '.'],
            'token_meanings': ['Hello', 'Marie', ''],
            'tip': 'Start with hello.',
          },
        ),
      },
    });
    expect(lesson.steps.first.target, 'Bonjour Marie');
    expect(lesson.steps.first.tokens, ['Bonjour', 'Marie']);
  });

  test('course grammar enters the exact native Grammar mode', () {
    final session = CourseArtifactCodec.grammarCourse({
      'practiceMode': 'complete',
      'session': {
        'id': 'grammar-course-1',
        'title': 'Dire son nom',
        'subtitle': 'Build one simple sentence.',
        'level': 'A1',
        'tense': 'Present',
        'grammar_focus': 'Je m’appelle',
        'icon_key': 'chat',
        'mode': 'complete',
        'goal': 'Say your name.',
        'source': 'generated',
        'steps': List.generate(
          5,
          (index) => {
            'label': 'Step ${index + 1}',
            'prompt': 'Construis la phrase.',
            'prompt_english': 'Build the sentence.',
            'target': 'Je m’appelle Sam.',
            'answer': 'Je m’appelle Sam.',
            'choices': <String>[],
            'tokens': ['Je', 'm’appelle', 'Sam.'],
            'tip': 'Put the subject first.',
          },
        ),
      },
    });
    expect(session.mode.name, 'complete');
    expect(session.steps, hasLength(5));
  });

  test('grammar decodes explanation, story, and quiz together', () {
    final artifact = storyArtifact()
      ..addAll({
        'grammarPoint': 'Le présent',
        'explanation': {
          'title': 'Le présent',
          'summary': 'Use it for current actions.',
          'usage': ['Describe what happens now.'],
          'tense_contrast': '',
          'conjugations': <Map<String, dynamic>>[],
          'examples': [
            {'fr': 'Elle ouvre la porte.', 'en': 'She opens the door.'},
          ],
        },
      });
    final grammar = CourseArtifactCodec.grammar(artifact);
    expect(grammar.grammarPoint, 'Le présent');
    expect(grammar.explanation.examples, hasLength(1));
  });
}
