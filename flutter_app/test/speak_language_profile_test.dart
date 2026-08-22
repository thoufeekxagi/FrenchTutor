import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/services/speak_language_profile.dart';

void main() {
  test('course copy follows the selected CEFR language mix', () {
    final a1 = SpeakLanguageProfile.forLevel('a1');
    final a2 = SpeakLanguageProfile.forLevel('a2');
    final b1 = SpeakLanguageProfile.forLevel('b1');
    final b2 = SpeakLanguageProfile.forLevel('b2');

    expect(
      [
        a1.englishPercent,
        a2.englishPercent,
        b1.englishPercent,
        b2.englishPercent,
      ],
      [85, 60, 40, 20],
    );
    expect(
      [a1.frenchPercent, a2.frenchPercent, b1.frenchPercent, b2.frenchPercent],
      [15, 40, 60, 80],
    );
    expect(a1.roadmapHint, contains('English'));
    expect(b2.roadmapHint, contains('Immersive French'));
  });

  test('legacy conversational profiles resolve to B1 guidance', () {
    expect(SpeakLanguageProfile.forLevel('conversational').level, 'B1');
  });

  test('each CEFR level has a distinct speaking difficulty ceiling', () {
    final profiles = [
      SpeakLanguageProfile.forLevel('A1'),
      SpeakLanguageProfile.forLevel('A2'),
      SpeakLanguageProfile.forLevel('B1'),
      SpeakLanguageProfile.forLevel('B2'),
    ];

    expect(profiles.map((profile) => profile.tutorTurnWordLimit).toList(), [
      '3–6 words',
      '5–9 words',
      '8–14 words',
      '10–18 words',
    ]);
    expect(profiles.map((profile) => profile.newWordsPerTurn).toList(), [
      1,
      2,
      4,
      6,
    ]);
    expect(
      profiles.every((profile) => profile.levelContract.isNotEmpty),
      isTrue,
    );
  });
}
