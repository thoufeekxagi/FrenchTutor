import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
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

    // Foundation (1-5) and Unit 2 (6-10) are both authored and fully
    // present the instant the plan is created.
    expect(roadmap.sessions, hasLength(10));
    expect(roadmap.trackLabel, 'Professional French');
    expect(roadmap.sessions.first.primarySkill, SpeakSkill.alphabet);
    expect(roadmap.sessions.first.contextPrompt, contains('Meetings'));
  });

  test('completion state and appended batches project into the roadmap', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    var expanded = store.ensureCurrentPlan(profile);
    for (var index = 0; index < 4; index++) {
      store.markCompleted(expanded.sessions.last.contentKey);
      expanded = store.ensureCurrentPlan(profile);
    }
    for (final session in expanded.sessions) {
      store.markCompleted(session.contentKey);
    }
    // The personalized route is unlimited: finishing everything prepared so
    // far does not end the course, it just grows one more row.
    expanded = store.ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: expanded.sessions,
    );

    expect(roadmap.sessions, hasLength(11));
    expect(roadmap.completedCount, 10);
    // The freshly appended row has no artifact yet in this store-only test,
    // so it is visible as "preparing" rather than actionable.
    expect(roadmap.nextSession, isNull);
    expect(roadmap.sessions.last.completed, isFalse);
    expect(roadmap.sessions.last.contentReady, isFalse);
  });

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

    // Sequences 6-10 (Unit 2) are always listed even while unready, since
    // that content is authored, not generated. Only sequence 11+ (real
    // personalized generation) still exposes just one pending placeholder.
    expect(roadmap.sessions, hasLength(11));
    expect(
      roadmap.sessions.where((session) => !session.contentReady),
      hasLength(6),
    );
    expect(roadmap.sessions.last.contentKey, 'pending-5');
  });
}
