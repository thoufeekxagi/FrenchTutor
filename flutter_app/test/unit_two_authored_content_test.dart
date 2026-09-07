import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/services/course_artifact_codec.dart';

void main() {
  test(
    'Unit 2 (sequences 6-10) is fully present and decodable the instant the plan is created',
    () {
      final stopwatch = Stopwatch()..start();
      final db = sqlite3.openInMemory();
      final store = AdaptiveCourseStore(db);
      final profile = Profile(id: 'verify', goal: 'everyday', level: 'a1');
      final plan = store.ensureCurrentPlan(profile);
      stopwatch.stop();

      print(
        'ensureCurrentPlan took ${stopwatch.elapsedMilliseconds}ms (no network)',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(500));

      // Foundation (1-5) and all of authored Unit 2 (6-10) exist immediately
      // — this is permanent default content for every learner, not
      // revealed one row at a time like real AI generation.
      expect(plan.sessions, hasLength(10));
      final bySeq = {for (final s in plan.sessions) s.sequence: s};

      final vocab = bySeq[6]!;
      expect(vocab.primarySkill, SpeakSkill.vocabulary);
      expect(vocab.generationStatus, 'ready');
      expect(vocab.isContentReady, isTrue);
      final vocabSet = CourseArtifactCodec.vocabulary(vocab.artifact!);
      expect(vocabSet.entries, hasLength(5));
      for (final entry in vocabSet.entries) {
        expect(entry.fr, isNotEmpty);
        expect(entry.en, isNotEmpty);
        expect(vocabSet.storyExamples[entry.id], isNotNull);
      }
      print(
        'vocabulary words: ${vocabSet.entries.map((e) => '${e.fr}=${e.en}').join(', ')}',
      );

      final speaking = bySeq[7]!;
      expect(speaking.primarySkill, SpeakSkill.speaking);
      expect(speaking.generationStatus, 'ready');
      expect(speaking.isContentReady, isTrue);
      final speakingLines = CourseArtifactCodec.speaking(speaking.artifact!);
      expect(speakingLines.length, greaterThanOrEqualTo(3));
      print(
        'speaking lines: ${speakingLines.map((l) => l.french).join(' | ')}',
      );

      final reading = bySeq[8]!;
      expect(reading.primarySkill, SpeakSkill.reading);
      expect(reading.generationStatus, 'ready');
      expect(reading.isContentReady, isTrue);
      final story = CourseArtifactCodec.story(reading.artifact!);
      expect(story.passage.segments, isNotEmpty);
      expect(story.quiz, isNotEmpty);
      print(
        'reading story: ${story.passage.segments.map((s) => s.fr).join(' ')}',
      );

      final listening = bySeq[9]!;
      expect(listening.primarySkill, SpeakSkill.listening);
      // Listening's durable audio is a single shared asset identical for
      // every learner (see generate-shared-course-listening-audio-once), so
      // this must be instantly ready like the rest of Unit 2 — no server
      // round trip, no per-learner render.
      expect(listening.artifact, isNotNull);
      expect(listening.artifact!['passage'], isNotNull);
      expect(listening.artifact!['audioPath'], isNotNull);
      expect(listening.generationStatus, 'ready');
      expect(listening.isContentReady, isTrue);
      print(
        'listening ready instantly with shared audio: ${listening.artifact!['audioPath']}',
      );

      final writing = bySeq[10]!;
      expect(writing.primarySkill, SpeakSkill.writing);
      expect(writing.generationStatus, 'ready');
      expect(writing.isContentReady, isTrue);
      final writingLesson = CourseArtifactCodec.writingCourse(
        writing.artifact!,
      );
      expect(writingLesson.steps, hasLength(5));
      for (final step in writingLesson.steps) {
        expect(step.choices, contains(step.target));
      }
      print(
        'writing steps: ${writingLesson.steps.map((s) => s.prompt).join(' | ')}',
      );
    },
  );
}
