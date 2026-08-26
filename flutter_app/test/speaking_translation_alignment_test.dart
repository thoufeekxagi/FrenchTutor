import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/speaking_course.dart';
import 'package:french_tutor/screens/speak/speaking_lesson_flow_screen.dart';
import 'package:french_tutor/utils/speaking_translation_alignment.dart';

void main() {
  test('every authored guided line has a complete translation alignment', () {
    final guidedLines = [
      for (final unit in SpeakingCourseCatalog.units)
        for (final lesson in unit.lessons)
          if (lesson.mode == SpeakingCourseMode.guided) ...lesson.lines,
    ];

    // The permanent catalog currently contains 43 guided lessons × 3 lines.
    expect(guidedLines, hasLength(129));
    for (final line in guidedLines) {
      final sourceCount = _wordCount(line.french);
      final translationCount = _wordCount(line.english);
      final alignment = SpeakingTranslationAlignment.forPhrase(
        line.french,
        line.english,
      );
      expect(alignment, hasLength(sourceCount), reason: line.french);
      for (var sourceIndex = 0; sourceIndex < alignment.length; sourceIndex++) {
        final sourceToken = line.french
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .elementAt(sourceIndex);
        if (_fold(sourceToken).isEmpty) continue;
        expect(alignment[sourceIndex], isNotEmpty, reason: line.french);
        expect(
          alignment[sourceIndex].every(
            (translationIndex) =>
                translationIndex >= 0 && translationIndex < translationCount,
          ),
          isTrue,
          reason: '${line.french} → ${line.english}',
        );
      }
    }
  });

  test(
    'authored name phrases map French chunks to the correct English words',
    () {
      final answer = SpeakingTranslationAlignment.forPhrase(
        'Je m’appelle Alex.',
        'My name is Alex.',
      );
      expect(answer[0], [0]);
      expect(answer[1], [1, 2]);
      expect(answer[2], [3]);

      final question = SpeakingTranslationAlignment.forPhrase(
        'Comment vous appelez-vous ?',
        'What is your name?',
      );
      expect(question[0], [0]);
      expect(question[1], [2]);
      expect(question[2], [3]);
    },
  );

  test(
    'generated guided scripts require bilingual, explicitly aligned phrases',
    () {
      const generatedTopics = [
        'introduce',
        'appointment',
        'clarification',
        'routine',
        'choice',
        'plan',
        'problem',
        'opinion',
        'direction',
        'preference',
        'request',
        'past',
        'natural',
        'connect',
      ];
      for (final topic in generatedTopics) {
        final steps = speakingStepsForLesson(
          targets: const [],
          title: topic,
          competency: topic,
          level: 'A1',
        );
        expect(steps, hasLength(4), reason: topic);
        expect(
          steps.every((step) => step.translationAlignment != null),
          isTrue,
          reason: topic,
        );
      }
    },
  );

  test(
    'every prepared Free Talk beat has authored hints and both alignments',
    () {
      final freeTalkLines = [
        for (final lesson in SpeakingCourseCatalog.freeTalkLessons)
          ...lesson.lines,
      ];
      expect(freeTalkLines, hasLength(132));
      for (final line in freeTalkLines) {
        expect(line.hintWords.length, greaterThanOrEqualTo(3));
        expect(line.hintWordsEnglish, hasLength(line.hintWords.length));
        expect(line.translationAlignment, isNotNull, reason: line.french);
        expect(
          line.partnerTranslationAlignment,
          isNotNull,
          reason: line.partnerFrench,
        );
        expect(
          line.translationAlignment!.any((indexes) => indexes.isNotEmpty),
          isTrue,
          reason: line.french,
        );
        for (final indexes in line.translationAlignment!) {
          if (indexes.isEmpty) continue;
          expect(indexes, everyElement(isA<int>()), reason: line.french);
        }
        expect(
          line.partnerTranslationAlignment!.any(
            (indexes) => indexes.isNotEmpty,
          ),
          isTrue,
          reason: line.partnerFrench,
        );
        for (final indexes in line.partnerTranslationAlignment!) {
          if (indexes.isEmpty) continue;
          expect(indexes, everyElement(isA<int>()), reason: line.partnerFrench);
        }
      }
    },
  );

  test('Free Talk selections map to the intended English meaning', () {
    final routineQuestion = SpeakingTranslationAlignment.forPhrase(
      'À quelle heure commence votre journée ?',
      'What time does your day start?',
    );
    expect(routineQuestion[3], [5], reason: 'commence → start');

    final nameQuestion = SpeakingTranslationAlignment.forPhrase(
      'Comment vous appelez-vous ?',
      'What is your name?',
    );
    expect(nameQuestion[1], [2], reason: 'vous → your');
    expect(nameQuestion[2], [3], reason: 'appelez-vous → name');
  });

  test('direction Roleplay words map to their intended English meaning', () {
    final tutor = SpeakingTranslationAlignment.forPhrase(
      'Bonjour, je peux vous aider ?',
      'Hello, can I help you?',
    );
    expect(tutor[4], [3], reason: 'aider → help');

    final learner = SpeakingTranslationAlignment.forPhrase(
      'Je tourne à gauche ?',
      'Do I turn left?',
    );
    expect(learner[1], [2], reason: 'tourne → turn');

    final direction = SpeakingTranslationAlignment.forPhrase(
      'Oui, puis tout droit.',
      'Yes, then straight ahead.',
    );
    expect(direction[1], [1], reason: 'puis → then');
    expect(direction[2], [2, 3], reason: 'tout droit → straight ahead');
  });

  test('every prepared Roleplay line has a complete bilingual alignment', () {
    final roleplayLines = [
      for (final lesson in SpeakingCourseCatalog.roleplays) ...lesson.lines,
    ];
    final failures = <String>[];
    for (final line in roleplayLines) {
      try {
        expect(line.partnerFrench, isNotNull, reason: line.french);
        expect(line.partnerEnglish, isNotNull, reason: line.french);
        final learner = SpeakingTranslationAlignment.forPhrase(
          line.french,
          line.english,
        );
        final partner = SpeakingTranslationAlignment.forPhrase(
          line.partnerFrench!,
          line.partnerEnglish!,
        );
        expect(
          learner,
          hasLength(_wordCount(line.french)),
          reason: line.french,
        );
        expect(
          partner,
          hasLength(_wordCount(line.partnerFrench!)),
          reason: line.partnerFrench,
        );
      } catch (error) {
        failures.add('$error');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('a future French-only target is rejected before it can render', () {
    expect(
      () => speakingStepsForTargets(const ['Une phrase future inconnue.']),
      throwsStateError,
    );
  });
}

int _wordCount(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

String _fold(String value) => value
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'''[.,!?;:«»'()…"]'''), '')
    .replaceAll('-', ' ')
    .trim();
