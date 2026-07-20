import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/utils/voice_card_command.dart';

void main() {
  test('recognizes the exact advance phrase, case/accent-insensitive', () {
    expect(matchesAdvanceCommand('Next word', nextPhrase: 'next word'), true);
    expect(matchesAdvanceCommand('NEXT SENTENCE', nextPhrase: 'next sentence'),
        true);
    expect(matchesAdvanceCommand('Carte suivante', nextPhrase: 'carte suivante'),
        true);
  });

  test('tolerates near-exact STT noise on the approved phrase', () {
    expect(
      matchesAdvanceCommand('next sentense', nextPhrase: 'next sentence'),
      true,
    );
  });

  test('rejects unrelated or loosely-related speech', () {
    expect(matchesAdvanceCommand('yes', nextPhrase: 'next word'), false);
    expect(matchesAdvanceCommand('oui', nextPhrase: 'next word'), false);
    expect(
      matchesAdvanceCommand('can we go to the next word', nextPhrase: 'next word'),
      false,
    );
    expect(
      matchesAdvanceCommand('the next word is hard', nextPhrase: 'next word'),
      false,
    );
    expect(
      matchesAdvanceCommand('background noise next word hello',
          nextPhrase: 'next word'),
      false,
    );
  });

  test('never matches a phrase approved for a different screen', () {
    expect(matchesAdvanceCommand('next word', nextPhrase: 'next sentence'), false);
  });
}
