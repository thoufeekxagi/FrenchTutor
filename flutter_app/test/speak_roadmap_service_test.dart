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

    expect(roadmap.sessions, hasLength(20));
    expect(roadmap.trackLabel, 'Professional French');
    expect(roadmap.sessions.first.primarySkill, SpeakSkill.alphabet);
    expect(roadmap.sessions.first.contextPrompt, contains('Meetings'));
  });

  test('completion state and appended batches project into the roadmap', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    final first = store.ensureCurrentPlan(profile);
    for (final session in first.sessions) {
      store.markCompleted(session.contentKey);
    }
    final expanded = store.ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: expanded.sessions,
    );

    expect(roadmap.sessions, hasLength(40));
    expect(roadmap.completedCount, 20);
    expect(roadmap.nextSession?.index, 20);
    expect(roadmap.sessions.every((session) => session.unlocked), isTrue);
  });

  test('adaptive projection retains all practice skill modes', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'tef_canada', level: 'b1');
    final plan = store.ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      adaptiveSessions: plan.sessions,
    );
    final skills = roadmap.sessions
        .map((session) => session.primarySkill)
        .toSet();

    expect(skills, contains(SpeakSkill.listening));
    expect(skills, contains(SpeakSkill.roleplay));
    expect(skills, contains(SpeakSkill.writing));
  });
}
