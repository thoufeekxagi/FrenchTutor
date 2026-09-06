import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:french_tutor/models/grammar_course.dart';
import 'package:french_tutor/models/writing_course.dart';
import 'package:french_tutor/services/learner_language_policy.dart';

void main() {
  test('A1 and A2 use English-first learner support', () {
    for (final level in ['A1', 'A2']) {
      final block = LearnerLanguagePolicy.promptBlock(level);
      expect(LearnerLanguagePolicy.isEnglishFirst(level), isTrue);
      expect(block, contains('English is the primary support language'));
      expect(block, contains('Every French sentence'));
    }
  });

  test('B1 and B2 keep accurate English support while increasing French', () {
    for (final level in ['B1', 'B2']) {
      final block = LearnerLanguagePolicy.promptBlock(level);
      expect(LearnerLanguagePolicy.isEnglishFirst(level), isFalse);
      expect(block, contains('English support fields'));
      expect(block, contains('French may lead'));
    }
  });

  test('generated lesson titles and icons follow their topic', () {
    final writing = WritingCourseLesson.fromJson({
      'id': 'writing-generated',
      'title': 'Les projets du week-end',
      'title_en': 'Weekend plans',
      'subtitle': 'Talk about weekend activities.',
      'level': 'A1',
      'mode': 'guided',
      'steps': [
        {
          'prompt': 'Je ___ au parc.',
          'prompt_english': 'I go to the park.',
          'target': 'Je vais au parc.',
          'kind': 'arrange',
          'tokens': ['Je', 'vais', 'au', 'parc.'],
          'token_meanings': ['I', 'go', 'to the', 'park.'],
        },
        {
          'prompt': 'Je ___ le matin.',
          'prompt_english': 'I work in the morning.',
          'target': 'Je travaille le matin.',
          'kind': 'arrange',
          'tokens': ['Je', 'travaille', 'le', 'matin.'],
          'token_meanings': ['I', 'work', 'the', 'morning.'],
        },
        {
          'prompt': 'Je ___ à midi.',
          'prompt_english': 'I eat at noon.',
          'target': 'Je mange à midi.',
          'kind': 'arrange',
          'tokens': ['Je', 'mange', 'à', 'midi.'],
          'token_meanings': ['I', 'eat', 'at', 'noon.'],
        },
        {
          'prompt': 'Je ___ un café.',
          'prompt_english': 'I order a coffee.',
          'target': 'Je commande un café.',
          'kind': 'arrange',
          'tokens': ['Je', 'commande', 'un', 'café.'],
          'token_meanings': ['I', 'order', 'a', 'coffee.'],
        },
        {
          'prompt': 'Je ___ dimanche.',
          'prompt_english': 'I rest on Sunday.',
          'target': 'Je me repose dimanche.',
          'kind': 'arrange',
          'tokens': ['Je', 'me', 'repose', 'dimanche.'],
          'token_meanings': ['I', 'myself', 'rest', 'Sunday.'],
        },
      ],
    });
    expect(writing.displayTitle, 'Weekend plans');
    expect(writing.icon, Icons.wb_sunny_outlined);

    final grammar = GrammarCourseSession.fromJson({
      'id': 'grammar-generated',
      'title': 'At the café',
      'subtitle': 'Order a drink with the present tense.',
      'level': 'A1',
      'tense': 'Present',
      'grammar_focus': 'Present tense',
      'icon_key': 'sparkles',
      'mode': 'guided',
      'source': 'generated',
      'steps': List.generate(
        5,
        (index) => {
          'label': 'Step ${index + 1}',
          'prompt': 'Je ___ un café.',
          'prompt_english': 'I order a coffee.',
          'target': 'Je prends un café.',
          'answer': 'prends',
          'choices': ['prends', 'prendre', 'prend'],
          'tip': 'Use the je form in the present tense.',
        },
      ),
    });
    expect(grammar.icon, Icons.local_cafe_outlined);
  });
}
