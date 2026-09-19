import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/services/course_generation_test_harness.dart';
import 'package:french_tutor/services/speak_roadmap_service.dart';

void main() {
  test('roadmap is projected only from the adaptive course plan', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(
      id: 'learner',
      goal: 'work',
      level: 'a1',
      interests: const ['Meetings'],
    );
    final plan = store.ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: plan.sessions,
    );

    // Foundation (1-5) and Unit 2 (6-11) are both authored and fully
    // present the instant the plan is created.
    expect(roadmap.sessions, hasLength(11));
    expect(roadmap.trackLabel, 'Professional French');
    expect(roadmap.sessions.first.primarySkill, SpeakSkill.alphabet);
    expect(roadmap.sessions.first.contextPrompt, contains('Meetings'));
  });

  test('same-skill successor projects into the roadmap', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    var expanded = store.ensureCurrentPlan(profile);
    final reading = expanded.sessions.firstWhere(
      (session) =>
          session.unit == 2 && session.primarySkill == SpeakSkill.reading,
    );
    store.markCompleted(reading.contentKey);
    expanded = store.ensureSuccessorForCompleted(profile, reading.contentKey);
    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: expanded.sessions,
    );

    expect(roadmap.sessions, hasLength(12));
    expect(roadmap.completedCount, 1);
    final successor = roadmap.sessions.firstWhere(
      (session) => session.unit == 3,
    );
    expect(successor.primarySkill, SpeakSkill.reading);
    expect(successor.completed, isFalse);
    expect(successor.contentReady, isFalse);
  });

  test(
    'debug grammar lane keeps restored ready Unit 3 skills visible on free account',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      const debugHarness = CourseGenerationTestHarness(
        enabled: true,
        skill: CourseGenerationHarnessSkill.grammar,
      );
      final store = AdaptiveCourseStore(db, generationHarness: debugHarness);
      final profile = Profile(
        id: 'restored-learner',
        goal: 'everyday',
        level: 'a1',
        sessionLength: 'standard',
        interests: const ['Speaking', 'Listening', 'Writing', 'Grammar'],
      );

      var plan = store.ensureCurrentPlan(profile);
      for (final skill in const [
        SpeakSkill.reading,
        SpeakSkill.listening,
        SpeakSkill.writing,
      ]) {
        plan = store.ensureSuccessorForSkill(profile, skill);
      }

      const readingArtifact =
          '{"passage":{"segments":['
          '{"fr":"Bonjour, je cherche la pharmacie.","en":"Hello, I am looking for the pharmacy."},'
          '{"fr":"Elle est près de la gare.","en":"It is near the station."}]},'
          '"quiz":[{},{},{}]}';
      const listeningArtifact =
          '{"passage":{"segments":['
          '{"fr":"Bonjour, je cherche la pharmacie.","en":"Hello, I am looking for the pharmacy."},'
          '{"fr":"Elle est près de la gare.","en":"It is near the station."}]},'
          '"quiz":[{},{},{}],"audioPath":"pcm-deck-v1:test",'
          '"audioMode":"pcm_deck_v1"}';
      const writingArtifact =
          '{"practiceMode":"guided","lesson":{"mode":"guided",'
          '"level":"A1","steps":[{},{},{},{},{}]}}';

      for (final session in plan.sessions.where((item) => item.unit == 3)) {
        final artifact = switch (session.primarySkill) {
          SpeakSkill.reading => readingArtifact,
          SpeakSkill.listening => listeningArtifact,
          SpeakSkill.writing => writingArtifact,
          _ => throw StateError('Unexpected Unit 3 skill'),
        };
        db.execute(
          "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
          'artifact_kind = ?, artifact_json = ? WHERE id = ?',
          [session.primarySkill.name, artifact, session.id],
        );
      }

      // A new store instance models the SQLite cache read after sign-in
      // hydration. Subscription and the debug-only generation lane are not
      // visibility filters: saved generated content stays on the roadmap.
      final restoredStore = AdaptiveCourseStore(
        db,
        generationHarness: debugHarness,
      );
      final restoredPlan = restoredStore.currentPlan(profile)!;
      final roadmap = SpeakRoadmapService.build(
        profile,
        adaptiveSessions: restoredPlan.sessions,
      );
      final unitThree = roadmap.sessions.where((session) => session.unit == 3);

      expect(unitThree, hasLength(3));
      expect(
        unitThree.map((session) => session.primarySkill).toSet(),
        containsAll([
          SpeakSkill.reading,
          SpeakSkill.listening,
          SpeakSkill.writing,
        ]),
      );
      expect(unitThree.every((session) => session.contentReady), isTrue);
    },
  );

  test('adaptive projection retains all practice skill modes', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(
      id: 'learner',
      goal: 'tef_canada',
      level: 'b1',
      interests: const ['Speaking', 'Listening', 'Writing'],
    );
    var plan = store.ensureCurrentPlan(profile);
    for (var index = 0; index < 4; index++) {
      store.markCompleted(plan.sessions.last.contentKey);
      plan = store.ensureCurrentPlan(profile);
    }
    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: plan.sessions,
    );
    final skills = roadmap.sessions
        .map((session) => session.primarySkill)
        .toSet();

    expect(skills, contains(SpeakSkill.listening));
    expect(skills, contains(SpeakSkill.writing));
  });

  test('legacy queued paths expose only one generating lesson', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a1');
    final initial = store.ensureCurrentPlan(profile);
    final foundation = initial.sessions.take(5).toList();
    final template = initial.sessions.last;
    final pending = List.generate(
      20,
      (index) => AdaptiveCourseSessionSpec(
        id: 'pending-$index',
        planId: template.planId,
        contentKey: 'pending-$index',
        sequence: 6 + index,
        level: template.level,
        unit: 2 + (index ~/ 5),
        unitTitle: template.unitTitle,
        title: template.title,
        subtitle: template.subtitle,
        competency: template.competency,
        context: template.context,
        primarySkill: template.primarySkill,
        supportingSkills: template.supportingSkills,
        grammarFocus: template.grammarFocus,
        successCriteria: template.successCriteria,
        estimatedMinutes: template.estimatedMinutes,
        generationStatus: 'queued',
        profileFingerprint: template.profileFingerprint,
        status: 'planned',
        createdAt: template.createdAt,
      ),
    );

    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: [...foundation, ...pending],
    );

    // Sequences 6-11 (Unit 2) are always listed even while unready, since
    // that content is authored, not generated. Only sequence 12+ (real
    // personalized generation) still exposes just one pending placeholder.
    expect(roadmap.sessions, hasLength(12));
    expect(
      roadmap.sessions.where((session) => !session.contentReady),
      hasLength(7),
    );
    expect(roadmap.sessions.last.contentKey, 'pending-6');
  });
}
