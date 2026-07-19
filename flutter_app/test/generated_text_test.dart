import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/utils/generated_text.dart';

void main() {
  test('normalizes em and en dashes from generated text', () {
    expect(
      normalizeGeneratedText('Bonjour — comment allez-vous ?'),
      'Bonjour, comment allez-vous ?',
    );
    expect(
      normalizeGeneratedText('Un choix – une réponse'),
      'Un choix, une réponse',
    );
  });
}
