import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/utils/voice_card_command.dart';

void main() {
  test('recognizes only exact approved voice commands', () {
    expect(exactVoiceCardCommand('Next card'), VoiceCardCommand.next);
    expect(
      exactVoiceCardCommand('Proceed to next card.'),
      VoiceCardCommand.next,
    );
    expect(exactVoiceCardCommand('Carte suivante'), VoiceCardCommand.next);
  });

  test('rejects ambiguous speech, conversational language, and noise', () {
    expect(exactVoiceCardCommand('yes'), isNull);
    expect(exactVoiceCardCommand('oui'), isNull);
    expect(exactVoiceCardCommand('can we go to the next card'), isNull);
    expect(exactVoiceCardCommand('the next card is hard'), isNull);
    expect(exactVoiceCardCommand('next card please'), isNull);
    expect(exactVoiceCardCommand('background noise next card hello'), isNull);
  });
}
