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

  test(
    'normalizes a completed transcript after its raw chunks are combined',
    () {
      const chunks = ['Ah, tu aimes ', 'lire ! C\'est ', 'noté.'];

      expect(
        normalizeGeneratedText(chunks.join()),
        'Ah, tu aimes lire ! C\'est noté.',
      );
    },
  );
}
