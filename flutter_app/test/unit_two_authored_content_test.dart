import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/services/course_artifact_codec.dart';

void main() {
  test('Unit 2 (sequences 6-10) is instantly ready with real, decodable content', () {
    final stopwatch = Stopwatch()..start();
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(id: 'verify', goal: 'everyday', level: 'a1');
    final plan = store.ensureCurrentPlan(profile);
    stopwatch.stop();

    print('ensureCurrentPlan took ${stopwatch.elapsedMilliseconds}ms (no network)');
    expect(stopwatch.elapsedMilliseconds, lessThan(500));

    expect(plan.sessions, hasLength(6)); // 5 foundation + vocab(6)
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
    print('vocabulary words: ${vocabSet.entries.map((e) => '${e.fr}=${e.en}').join(', ')}');

    // Growing one step (as if the learner finished vocabulary) must reveal
    // speaking, already ready, with zero extra delay.
    final afterVocab = store.ensureCurrentPlan(profile);
    expect(afterVocab.sessions, hasLength(7));
    final speaking = afterVocab.sessions.firstWhere((s) => s.sequence == 7);
    expect(speaking.primarySkill, SpeakSkill.speaking);
    expect(speaking.generationStatus, 'ready');
    expect(speaking.isContentReady, isTrue);
    final speakingLines = CourseArtifactCodec.speaking(speaking.artifact!);
    expect(speakingLines.length, greaterThanOrEqualTo(3));
    print('speaking lines: ${speakingLines.map((l) => l.french).join(' | ')}');

    // Grow one more step to see reading (8).
    store.markCompleted(vocab.contentKey);
    var grown = store.ensureCurrentPlan(profile);
    store.markCompleted(speaking.contentKey);
    grown = store.ensureCurrentPlan(profile);
    final reading = grown.sessions.firstWhere((s) => s.sequence == 8);
    expect(reading.primarySkill, SpeakSkill.reading);
    expect(reading.generationStatus, 'ready');
    expect(reading.isContentReady, isTrue);
    final story = CourseArtifactCodec.story(reading.artifact!);
    expect(story.passage.segments, isNotEmpty);
    expect(story.quiz, isNotEmpty);
    print('reading story: ${story.passage.segments.map((s) => s.fr).join(' ')}');

    store.markCompleted(reading.contentKey);
    grown = store.ensureCurrentPlan(profile);
    final listening = grown.sessions.firstWhere((s) => s.sequence == 9);
    expect(listening.primarySkill, SpeakSkill.listening);
    // Listening's text is ready but audio is not attached without the
    // server call, so it must correctly report not-ready, not crash and
    // not claim readiness it does not have.
    expect(listening.artifact, isNotNull);
    expect(listening.artifact!['passage'], isNotNull);
    expect(listening.isContentReady, isFalse);
    print('listening text ready, audio pending as expected: ${listening.generationStatus}');

    // Writing (10) only appears once listening is also out of the way in a
    // real flow, but its artifact is already built eagerly by the generator
    // for this plan, so validate it directly via the generator too.
    final generated = AdaptiveCoursePlanGenerator.generate(
      profile: profile,
      planId: 'verify-plan',
      profileFingerprint: 'fp',
      startSequence: 1,
      count: 10,
    );
    final writing = generated.firstWhere((s) => s.sequence == 10);
    expect(writing.primarySkill, SpeakSkill.writing);
    expect(writing.generationStatus, 'ready');
    expect(writing.isContentReady, isTrue);
    final writingLesson = CourseArtifactCodec.writingCourse(writing.artifact!);
    expect(writingLesson.steps, hasLength(5));
    for (final step in writingLesson.steps) {
      expect(step.choices, contains(step.target));
    }
    print('writing steps: ${writingLesson.steps.map((s) => s.prompt).join(' | ')}');
  });
}
