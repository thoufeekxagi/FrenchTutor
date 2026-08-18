import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/story_variety_service.dart';

void main() {
  test('surprise seeds avoid matching recent story words', () {
    final seed = StoryVarietyService.chooseSeed(
      avoidTexts: const [
        'A handwritten note tucked under a café table',
        'A lost library card found inside a returned book',
      ],
    );

    expect(seed, isNot('a handwritten note tucked under a café table'));
    expect(seed, isNot('a lost library card found inside a returned book'));
  });

  test('duplicate guard rejects repeated title or opening', () {
    expect(
      StoryVarietyService.isDuplicate(
        title: 'Le petit chat bleu',
        opening: 'Le chat marche dans la rue.',
        avoidTitles: const ['Le petit chat bleu'],
      ),
      isTrue,
    );
    expect(
      StoryVarietyService.isDuplicate(
        title: 'Une histoire différente',
        opening: 'Le chat marche dans la rue.',
        avoidOpenings: const ['Le chat marche dans la rue.'],
      ),
      isTrue,
    );
    expect(
      StoryVarietyService.isDuplicate(
        title: 'Le vélo oublié',
        opening: 'La pluie tombe sur le quai.',
        avoidTitles: const ['Le petit chat bleu'],
        avoidOpenings: const ['Le chat marche dans la rue.'],
      ),
      isFalse,
    );
  });

  test('story fingerprint normalizes equivalent cards', () {
    expect(
      StoryVarietyService.storyFingerprint(
        title: 'Le petit chat bleu!',
        opening: 'Le chat marche dans la rue.',
      ),
      StoryVarietyService.storyFingerprint(
        title: 'LE PETIT CHAT BLEU',
        opening: 'Le chat marche dans la rue',
      ),
    );
  });
}
