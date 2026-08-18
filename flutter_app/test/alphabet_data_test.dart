import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/data/alphabet_data.dart';
import 'package:french_tutor/models/tutor_persona.dart';

void main() {
  test('vowel cards speak the letter name, not the example word', () {
    const expectedSpokenNames = {
      'A': 'a',
      'E': 'e',
      'I': 'i',
      'O': 'o',
      'U': 'u',
      'Y': 'i grec',
    };

    for (final entry in expectedSpokenNames.entries) {
      final letter = frenchAlphabet.firstWhere(
        (candidate) => candidate.letter == entry.key,
      );

      expect(alphabetSpokenText(letter), entry.value);
      expect(alphabetSpokenText(letter), isNot(letter.exampleWord));
    }
  });

  test(
    'alphabet audio identity is shared by full, vowel, and consonant decks',
    () {
      for (final letter in frenchAlphabet) {
        expect(alphabetAudioId(letter), startsWith('alphabet_letter_'));
        expect(
          alphabetAudioAssetPath(letter, TutorPersona.all.first),
          contains(alphabetAudioId(letter)),
        );
      }
    },
  );

  test('the foundation accent deck contains the three core accent marks', () {
    expect(coreAccentLetters.map((letter) => letter.letter), ['É', 'È', 'Ê']);
    expect(coreAccentLetters.map((letter) => letter.phonetic), [
      'accent aigu',
      'accent grave',
      'accent circonflexe',
    ]);
  });

  test(
    'every letter, vowel, and accent has a bundled clip for every tutor',
    () {
      expect(frenchAlphabet, hasLength(26));
      expect(vowelLetters.map((letter) => letter.letter), [
        'A',
        'E',
        'I',
        'O',
        'U',
        'Y',
      ]);
      expect(frenchAccents.map((letter) => letter.letter), [
        'É',
        'È',
        'Ê',
        'Ç',
        'Ë',
      ]);

      final items = alphabetPrewarmItems();
      expect(items, hasLength(TutorPersona.all.length * 31));
      expect(items.map((item) => item.contentItemId).toSet(), hasLength(31));

      for (final item in items) {
        final assetPath = item.assetPath!;
        expect(
          File(assetPath).existsSync(),
          isTrue,
          reason: 'Missing bundled alphabet audio: $assetPath',
        );
        expect(File(assetPath).lengthSync(), greaterThan(0));
      }
    },
  );
}
