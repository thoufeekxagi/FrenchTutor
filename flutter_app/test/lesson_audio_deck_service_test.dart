import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:typed_data';

import 'package:french_tutor/data/database/app_migrations.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/services/lesson_audio_deck_service.dart';

void main() {
  test('shared Unit 2 WAV is parsed and split locally without a provider', () {
    final pcm = Uint8List.fromList(List<int>.filled(24000 * 2, 1200));
    final wav = _wavPcm16Mono24k(pcm);
    final extracted = LessonAudioDeckService.extractPcm16Wav(wav);
    expect(extracted, orderedEquals(pcm));

    final chunks = LessonAudioDeckService.splitPcmIntoSegments(pcm, const [
      'Une phrase.',
      'Une autre phrase.',
      'La dernière phrase.',
    ]);
    expect(chunks, hasLength(3));
    expect(chunks.fold<int>(0, (sum, chunk) => sum + chunk.length), pcm.length);
  });

  test(
    'shared course path is recognized as a local import, not a Live deck',
    () {
      final story = GeneratedStory(
        id: 'unit-two-listening',
        passage: ReadingPassage(
          id: 'p',
          title: 'The market closes',
          fullText: 'Le soir.',
          segments: [
            ReadingSegment(
              fr: 'Le soir.',
              en: 'In the evening.',
              grammarNote: '',
              pronunciationTip: '',
            ),
          ],
        ),
        quiz: const [],
        keywords: const [],
        createdAt: DateTime(2026),
        audioPath: 'course-shared/unit-two-listening.wav',
        audioMode: 'gemini_flash_tts',
        practiceMode: 'listening',
      );
      expect(LessonAudioDeckService.usesSharedCourseWav(story), isTrue);
      expect(
        LessonAudioDeckService.usesSharedCourseWav(
          story.copyWith(
            audioPath: 'pcm-deck-v1:unit-two-listening',
            audioMode: 'pcm_deck_v1',
          ),
        ),
        isTrue,
      );
    },
  );

  test('migration creates a durable sentence deck manifest', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    runAppMigrations(db);

    final columns = db.select('PRAGMA table_info(lesson_audio_decks)');
    expect(
      columns.map((row) => row['name']),
      containsAll(<String>[
        'lesson_id',
        'segment_index',
        'spoken_text',
        'voice_name',
        'cache_key',
        'status',
        'updated_at',
      ]),
    );
  });

  test('prepared status requires every sentence in the lesson', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    runAppMigrations(db);
    final story = GeneratedStory(
      id: 'deck-test',
      passage: ReadingPassage(
        id: 'passage',
        title: 'Test',
        fullText: 'Bonjour. Au revoir.',
        segments: [
          ReadingSegment(
            fr: 'Bonjour.',
            en: 'Hello.',
            grammarNote: '',
            pronunciationTip: '',
          ),
          ReadingSegment(
            fr: 'Au revoir.',
            en: 'Goodbye.',
            grammarNote: '',
            pronunciationTip: '',
          ),
        ],
      ),
      quiz: const [],
      keywords: const [],
      createdAt: DateTime(2026),
    );
    final voice = ActiveTutor.current.voiceName;
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''INSERT INTO lesson_audio_decks
         (lesson_id, segment_index, spoken_text, voice_name, cache_key, status, updated_at)
         VALUES (?, ?, ?, ?, ?, 'local_ready', ?)''',
      [story.id, 0, 'Bonjour.', voice, 'one', now],
    );

    expect(
      LessonAudioDeckService.shared.isPrepared(story: story, db: db),
      isFalse,
    );
    db.execute(
      '''INSERT INTO lesson_audio_decks
         (lesson_id, segment_index, spoken_text, voice_name, cache_key, status, updated_at)
         VALUES (?, ?, ?, ?, ?, 'local_ready', ?)''',
      [story.id, 1, 'Au revoir.', voice, 'two', now],
    );
    expect(
      LessonAudioDeckService.shared.isPrepared(story: story, db: db),
      isTrue,
    );
  });
}

Uint8List _wavPcm16Mono24k(Uint8List pcm) {
  final bytes = Uint8List(44 + pcm.length);
  bytes.setRange(44, bytes.length, pcm);
  final view = ByteData.sublistView(bytes);
  void fourCc(int offset, String value) {
    bytes.setRange(offset, offset + 4, value.codeUnits);
  }

  fourCc(0, 'RIFF');
  view.setUint32(4, 36 + pcm.length, Endian.little);
  fourCc(8, 'WAVE');
  fourCc(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, 24000, Endian.little);
  view.setUint32(28, 48000, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  fourCc(36, 'data');
  view.setUint32(40, pcm.length, Endian.little);
  return bytes;
}
