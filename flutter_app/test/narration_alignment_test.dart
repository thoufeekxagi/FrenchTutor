import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/utils/narration_alignment.dart';

void main() {
  test('merges cumulative and partial Live transcript updates', () {
    var transcript = '';
    transcript = NarrationAlignment.appendTranscriptDelta(transcript, 'Le mar');
    transcript = NarrationAlignment.appendTranscriptDelta(transcript, 'marché');
    transcript = NarrationAlignment.appendTranscriptDelta(
      transcript,
      'Le marché est',
    );

    expect(transcript, 'Le marché est');
  });

  test('does not advance on a partial prefix of the next word', () {
    expect(
      NarrationAlignment.currentWordIndex('Le marché est vivant', 'Le mar'),
      1,
    );
    expect(
      NarrationAlignment.currentWordIndex(
        'Le marché est vivant',
        'Le marché es',
      ),
      2,
    );
  });

  test('keeps French elisions aligned when transcription inserts a space', () {
    expect(
      NarrationAlignment.currentWordIndex(
        "L'information est ici",
        'L information est',
      ),
      1,
    );
  });

  test('ignores punctuation and accents without shifting indexes', () {
    expect(
      NarrationAlignment.currentWordIndex(
        'Élodie va au marché.',
        'Elodie va au marché',
      ),
      3,
    );
  });
}
