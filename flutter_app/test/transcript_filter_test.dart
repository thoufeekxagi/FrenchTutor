import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/utils/transcript_filter.dart';

void main() {
  group('isFrenchEnglishTranscript', () {
    test('keeps English', () {
      expect(isFrenchEnglishTranscript('Can you repeat that please?'), isTrue);
    });

    test('keeps French with accents and ligatures', () {
      expect(
        isFrenchEnglishTranscript("Très bien! Je m'appelle Éloïse, ça va?"),
        isTrue,
      );
      expect(isFrenchEnglishTranscript('un cœur, une sœur, Noël'), isTrue);
    });

    test('keeps numbers and punctuation-only lines', () {
      expect(isFrenchEnglishTranscript('12, 34 — ...?'), isTrue);
      expect(isFrenchEnglishTranscript(''), isTrue);
    });

    test('omits Malayalam', () {
      expect(isFrenchEnglishTranscript('എനിക്ക് ഫ്രഞ്ച് പഠിക്കണം'), isFalse);
    });

    test('omits Tamil', () {
      expect(isFrenchEnglishTranscript('எனக்கு பிரெஞ்சு கற்க வேண்டும்'), isFalse);
    });

    test('omits Hindi', () {
      expect(isFrenchEnglishTranscript('मुझे फ्रेंच सीखनी है'), isFalse);
    });

    test('omits Arabic', () {
      expect(isFrenchEnglishTranscript('أريد أن أتعلم الفرنسية'), isFalse);
    });

    test('omits Chinese', () {
      expect(isFrenchEnglishTranscript('我想学法语'), isFalse);
    });

    test('omits Korean and Japanese', () {
      expect(isFrenchEnglishTranscript('프랑스어를 배우고 싶어요'), isFalse);
      expect(isFrenchEnglishTranscript('フランス語を勉強したい'), isFalse);
    });

    test('omits Russian', () {
      expect(isFrenchEnglishTranscript('Я хочу выучить французский'), isFalse);
    });

    test('a stray foreign character does not nuke a French line', () {
      expect(
        isFrenchEnglishTranscript('Je voudrais un croissant с plaisir'),
        isTrue,
      );
    });

    test('mostly-foreign mixed line is omitted', () {
      expect(
        isFrenchEnglishTranscript('ok എനിക്ക് ഫ്രഞ്ച് പഠിക്കണം വേഗം'),
        isFalse,
      );
    });
  });
}
