import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';

void main() {
  test(
    'fresh learner gets twenty adaptive session specifications immediately',
    () {
      final store = AdaptiveCourseStore(sqlite3.openInMemory());
      final plan = store.ensureCurrentPlan(
        Profile(
          id: 'learner',
          goal: 'work',
          level: 'a1',
          interests: const ['Meetings', 'Emails'],
        ),
      );

      expect(plan.sessions, hasLength(20));
      expect(
        plan.sessions.map((session) => session.contentKey).toSet(),
        hasLength(20),
      );
      expect(plan.sessions.first.context, contains('Meetings'));
      expect(plan.sessions.every((session) => session.level == 'A1'), isTrue);
      expect(
        plan.sessions.map((session) => session.competency).toSet().length,
        greaterThan(10),
      );
      expect(plan.sessions.take(5).map((session) => session.title), [
        'Recognize French sounds',
        'Build vowel confidence',
        'Notice French consonants',
        'Recognize core accent marks',
        'Connect sound to meaning',
      ]);
      expect(
        plan.sessions
            .take(4)
            .every((session) => session.primarySkill == SpeakSkill.alphabet),
        isTrue,
      );
      expect(plan.sessions[4].primarySkill, SpeakSkill.vocabulary);
      expect(plan.sessions.skip(5).first.title, 'Write a short message');
      expect(plan.sessions.skip(5).first.unitTitle, isNotEmpty);
      expect(plan.sessions.skip(5).first.title, isNot(contains('Meetings')));
    },
  );

  test(
    'a single selected focus weights future sessions without removing support',
    () {
      final store = AdaptiveCourseStore(sqlite3.openInMemory());
      final plan = store.ensureCurrentPlan(
        Profile(
          id: 'listener',
          goal: 'everyday',
          level: 'a2',
          interests: const ['Listening'],
        ),
      );

      expect(
        plan.sessions
            .skip(3)
            .every(
              (session) =>
                  session.primarySkill == SpeakSkill.listening ||
                  session.primarySkill == SpeakSkill.reading,
            ),
        isTrue,
      );
    },
  );

  test('the next twenty are appended when five or fewer remain', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    final first = store.ensureCurrentPlan(profile);

    for (final session in first.sessions.take(15)) {
      store.markCompleted(session.contentKey);
    }
    final expanded = store.ensureCurrentPlan(profile);

    expect(expanded.sessions, hasLength(40));
    expect(
      expanded.sessions
          .take(15)
          .every((session) => session.status == 'completed'),
      isTrue,
    );
    expect(expanded.sessions.last.sequence, 40);
  });

  test(
    'profile changes preserve completed sessions and replace future context',
    () {
      final store = AdaptiveCourseStore(sqlite3.openInMemory());
      final original = Profile(id: 'learner', goal: 'everyday', level: 'a1');
      final first = store.ensureCurrentPlan(original);
      for (final session in first.sessions.take(5)) {
        store.markCompleted(session.contentKey);
      }

      final changed = store.ensureCurrentPlan(
        Profile(
          id: 'learner',
          goal: 'work',
          level: 'a1',
          interests: const ['Meetings'],
        ),
      );

      expect(changed.version, 2);
      expect(
        changed.sessions
            .take(5)
            .every((session) => session.status == 'completed'),
        isTrue,
      );
      expect(
        changed.sessions.take(5).map((session) => session.contentKey),
        first.sessions.take(5).map((session) => session.contentKey),
      );
      expect(changed.sessions.skip(5).first.context, contains('Meetings'));
      expect(
        changed.sessions.skip(5).first.subtitle,
        contains('Professional French'),
      );
    },
  );

  test('stale interests do not leak into a new goal', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final plan = store.ensureCurrentPlan(
      Profile(
        id: 'learner',
        goal: 'relocation',
        level: 'a2',
        interests: const ['Meetings'],
      ),
    );

    expect(plan.sessions.first.context, isNot(contains('Meetings')));
    expect(plan.sessions.first.context, contains('housing'));
  });

  test('pre-auth plans keep their identity when adopted by an account', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(id: 'learner', goal: 'work', level: 'a1');
    db.execute(
      'INSERT INTO profiles (id, created_at, updated_at) VALUES (?, ?, ?)',
      [profile.id, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'],
    );
    final before = store.ensureCurrentPlan(profile);

    db.execute('UPDATE profiles SET user_id = ? WHERE id = ?', [
      'supabase-user',
      profile.id,
    ]);
    store.linkSupabaseUser('supabase-user');

    final after = store.ensureCurrentPlan(profile);
    expect(after.id, before.id);
    expect(after.sessions, hasLength(20));
  });

  test('remote plan and session rows hydrate into the local route', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    db.execute(
      'INSERT INTO profiles (id, created_at, updated_at) VALUES (?, ?, ?)',
      [profile.id, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'],
    );
    final generated = store.ensureCurrentPlan(profile);
    final session = generated.sessions.first;
    const remoteUserId = 'remote-user';
    final later = '2099-01-01T00:00:00.000Z';

    db.execute('UPDATE profiles SET user_id = ? WHERE id = ?', [
      remoteUserId,
      profile.id,
    ]);
    store.linkSupabaseUser(remoteUserId);
    store.upsertPlanFromRemote({
      'id': generated.id,
      'user_id': remoteUserId,
      'goal': generated.goal,
      'level': generated.level,
      'profile_fingerprint': generated.profileFingerprint,
      'version': generated.version,
      'status': 'active',
      'created_at': later,
      'updated_at': later,
      'deleted_at': null,
    });
    store.upsertSessionFromRemote({
      'id': session.id,
      'user_id': remoteUserId,
      'plan_id': generated.id,
      'content_key': session.contentKey,
      'sequence': session.sequence,
      'level': session.level,
      'unit': session.unit,
      'unit_title': session.unitTitle,
      'title': session.title,
      'subtitle': session.subtitle,
      'competency': session.competency,
      'context': session.context,
      'primary_skill': session.primarySkill.wireName,
      'supporting_skills_json': session.supportingSkills
          .map((skill) => skill.wireName)
          .toList(),
      'grammar_focus_json': session.grammarFocus,
      'success_criteria_json': session.successCriteria,
      'estimated_minutes': session.estimatedMinutes,
      'profile_fingerprint': session.profileFingerprint,
      'status': 'completed',
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': later,
      'completed_at': later,
      'deleted_at': null,
    });

    expect(store.currentPlan(profile)!.sessions.first.status, 'completed');
  });
}
