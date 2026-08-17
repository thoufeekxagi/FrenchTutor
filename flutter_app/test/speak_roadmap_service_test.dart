import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/services/speak_curriculum_catalog.dart';
import 'package:french_tutor/services/speak_roadmap_service.dart';

void main() {
  test('level choice produces the expected long-form course path', () {
    final a1 = SpeakRoadmapService.build(Profile(id: 'a1', level: 'a1'));
    final a2 = SpeakRoadmapService.build(Profile(id: 'a2', level: 'a2'));
    final b1 = SpeakRoadmapService.build(Profile(id: 'b1', level: 'b1'));
    final b2 = SpeakRoadmapService.build(Profile(id: 'b2', level: 'b2'));

    expect(a1.sessions, hasLength(120));
    expect(a2.sessions, hasLength(140));
    expect(b1.sessions, hasLength(160));
    expect(b2.sessions, hasLength(200));
  });

  test(
    'roadmap keeps every session available while progress recommends next',
    () {
      final roadmap = SpeakRoadmapService.build(
        Profile(id: 'learner', level: 'a1'),
        completedSessions: 7,
      );

      expect(roadmap.completedCount, 7);
      expect(roadmap.progress, closeTo(7 / 120, 0.0001));
      expect(roadmap.nextSession?.index, 7);
      expect(roadmap.sessions[7].unlocked, isTrue);
      expect(roadmap.sessions.every((session) => session.unlocked), isTrue);
    },
  );

  test(
    'roadmap starts at Unit 1 even when catalog rows arrive out of order',
    () {
      final items = SpeakCurriculumCatalog.bundled('A1').reversed.toList();
      final roadmap = SpeakRoadmapService.build(
        Profile(id: 'learner', level: 'a1'),
        catalog: items,
      );

      expect(roadmap.sessions.first.unit, 1);
      expect(roadmap.sessions.first.index, 0);
      expect(roadmap.sessions.last.unit, 12);
    },
  );

  test('course path includes the requested review and speaking modes', () {
    final roadmap = SpeakRoadmapService.build(
      Profile(id: 'learner', level: 'b1'),
    );
    final kinds = roadmap.sessions.map((session) => session.kind).toSet();

    expect(kinds, contains(SpeakSessionKind.review));
    expect(kinds, contains(SpeakSessionKind.roleplay));
    expect(kinds, contains(SpeakSessionKind.story));
  });
}
