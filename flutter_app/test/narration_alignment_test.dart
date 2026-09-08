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

  test(
    'playback pacing does not jump to the final word on a full transcript',
    () {
      const sentence = 'Je prends le train demain';
      const queued = Duration(seconds: 2);

      final early = NarrationAlignment.playbackWordIndex(
        sentence,
        playbackPosition: const Duration(milliseconds: 180),
        queuedAudioDuration: queued,
        transcriptWordIndex: 4,
      );
      final middle = NarrationAlignment.playbackWordIndex(
        sentence,
        playbackPosition: const Duration(milliseconds: 1050),
        queuedAudioDuration: queued,
        transcriptWordIndex: 4,
      );

      expect(early, isNot(4));
      expect(middle, isNot(4));
      expect(middle, greaterThan(early!));
    },
  );

  test('transcript progress remains a ceiling for playback pacing', () {
    final index = NarrationAlignment.playbackWordIndex(
      'Je prends le train demain',
      playbackPosition: const Duration(seconds: 4),
      queuedAudioDuration: const Duration(seconds: 4),
      transcriptWordIndex: 1,
    );

    expect(index, lessThanOrEqualTo(1));
  });
}
