import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/models/speaking_course.dart';

/// Minimal but validator-satisfying A1 artifact JSON for each personalized
/// skill, used to drive `AdaptiveCourseStore`'s one-row-at-a-time growth
/// forward in tests without a real generation pipeline.
String _readyArtifactFor(SpeakSkill skill) {
  switch (skill) {
    case SpeakSkill.vocabulary:
      return '{"entries":['
          '{"id":"e1","en":"one","fr":"un","phonetic":"uh"},'
          '{"id":"e2","en":"two","fr":"deux","phonetic":"duh"},'
          '{"id":"e3","en":"three","fr":"trois","phonetic":"twah"},'
          '{"id":"e4","en":"four","fr":"quatre","phonetic":"katr"},'
          '{"id":"e5","en":"five","fr":"cinq","phonetic":"sank"}'
          '],"storyExamples":{'
          '"e1":{"fr":"Un chat.","en":"One cat."},'
          '"e2":{"fr":"Deux chats.","en":"Two cats."},'
          '"e3":{"fr":"Trois chats.","en":"Three cats."},'
          '"e4":{"fr":"Quatre chats.","en":"Four cats."},'
          '"e5":{"fr":"Cinq chats.","en":"Five cats."}'
          '}}';
    case SpeakSkill.reading:
      return '{"passage":{"segments":['
          '{"fr":"Bonjour.","en":"Hello."},'
          '{"fr":"Ça va bien.","en":"I am well."}'
          ']},"quiz":[{"q":"Ça va ?","choices":["Oui","Non"],"answerIndex":0}]}';
    case SpeakSkill.listening:
      return '{"passage":{"segments":['
          '{"fr":"Bonjour.","en":"Hello."},'
          '{"fr":"Ça va bien.","en":"I am well."}'
          ']},"quiz":[{"q":"Ça va ?","choices":["Oui","Non"],"answerIndex":0}],'
          '"audioPath":"user/course/listening.wav",'
          '"audioMode":"gemini_flash_tts"}';
    default:
      return '{"practiceMode":"guidedConversation","lines":['
          '{"fr":"Bonjour.","en":"Hello."},'
          '{"fr":"Je m\'appelle Léa.","en":"My name is Lea."},'
          '{"fr":"Merci beaucoup.","en":"Thank you very much."}'
          ']}';
  }
}

/// Marks the given session ready with valid content, then immediately
/// completes it (as if the learner finished the lesson) so the store's
/// "never more than two ready-ahead" rule does not stall growth in a loop.
void _finishSession(
  CommonDatabase db,
  AdaptiveCourseStore store,
  AdaptiveCourseSessionSpec session,
) {
  db.execute(
    "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
    'artifact_json = ? WHERE id = ?',
    [_readyArtifactFor(session.primarySkill), session.id],
  );
  store.markCompleted(session.contentKey);
}

void main() {
  test('listening stays unready until its durable PCM WAV is attached', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(
      id: 'listener-ready-contract',
      goal: 'everyday',
      level: 'a1',
      interests: const ['Listening'],
    );
    // Every personalized unit is taught in a fixed order (vocabulary,
    // speaking, reading, listening, writing), so listening is the fourth
    // personalized row. Grow the plan up to it the same way the app does:
    // one row at a time, only after the previous one is marked ready.
    var plan = store.ensureCurrentPlan(profile);
    while (!plan.sessions.any(
      (session) => !session.isFoundation && session.primarySkill == SpeakSkill.listening,
    )) {
      _finishSession(db, store, plan.sessions.last);
      plan = store.ensureCurrentPlan(profile);
    }
    final listening = plan.sessions.firstWhere(
      (session) =>
          !session.isFoundation && session.primarySkill == SpeakSkill.listening,
    );
    const passageOnly =
        '{"passage":{"segments":[{"fr":"Bonjour.","en":"Hello."},'
        '{"fr":"Ça va bien.","en":"I am well."}]},'
        '"quiz":[{"q":"Ça va ?","choices":["Oui","Non"],"answerIndex":0}]}';
    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      'artifact_json = ? WHERE id = ?',
      [passageOnly, listening.id],
    );
    expect(store.sessionById(listening.id)!.isContentReady, isFalse);

    const complete =
        '{"passage":{"segments":[{"fr":"Bonjour.","en":"Hello."},'
        '{"fr":"Ça va bien.","en":"I am well."}]},'
        '"quiz":[{"q":"Ça va ?","choices":["Oui","Non"],"answerIndex":0}],'
        '"audioPath":"user/course/listening.wav",'
        '"audioMode":"gemini_flash_tts"}';
    db.execute(
      'UPDATE adaptive_course_sessions SET artifact_json = ? WHERE id = ?',
      [complete, listening.id],
    );
    expect(store.sessionById(listening.id)!.isContentReady, isTrue);
  });

  test('a cached A1 artifact is not ready when its French is over-level', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(
      id: 'a1-content-contract',
      goal: 'everyday',
      level: 'a1',
      interests: const ['Speaking'],
    );
    // Speaking is the second personalized row (after vocabulary); mark the
    // vocabulary row ready first so the store grows to it.
    var plan = store.ensureCurrentPlan(profile);
    while (!plan.sessions.any(
      (session) => !session.isFoundation && session.primarySkill == SpeakSkill.speaking,
    )) {
      _finishSession(db, store, plan.sessions.last);
      plan = store.ensureCurrentPlan(profile);
    }
    final speaking = plan.sessions.firstWhere(
      (session) =>
          !session.isFoundation &&
          session.primarySkill == SpeakSkill.speaking &&
          session.status != 'completed',
    );
    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      'artifact_json = ? WHERE id = ?',
      [
        '{"lines":[{"fr":"Si j\'avais le temps, je pourrais expliquer mon opinion sur ce sujet.","en":"If I had time, I could explain my opinion on this topic."},{"fr":"Bonjour.","en":"Hello."},{"fr":"Merci.","en":"Thank you."}]}',
        speaking.id,
      ],
    );
    expect(store.sessionById(speaking.id)!.isContentReady, isFalse);
  });

  test(
    'fresh learner gets five foundations and a full authored Unit 2',
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

      // Foundation (1-5) and Unit 2 (6-10) are both authored, permanent
      // default content for every learner: all ten rows exist immediately,
      // no waiting, no AI call.
      expect(plan.sessions, hasLength(10));
      expect(
        plan.sessions.map((session) => session.contentKey).toSet(),
        hasLength(10),
      );
      expect(plan.sessions.first.context, contains('Meetings'));
      expect(plan.sessions.every((session) => session.level == 'A1'), isTrue);
      expect(
        plan.sessions.map((session) => session.competency).toSet().length,
        greaterThan(4),
      );
      expect(plan.sessions.take(5).map((session) => session.title), [
        'Recognize French sounds',
        'Build vowel confidence',
        'Notice French consonants',
        'Recognize core accent marks',
        'Introduce yourself',
      ]);
      expect(
        plan.sessions
            .take(4)
            .every((session) => session.primarySkill == SpeakSkill.alphabet),
        isTrue,
      );
      expect(plan.sessions[4].primarySkill, SpeakSkill.speaking);
      expect(
        plan.sessions[4].contentKey,
        SpeakingCourseCatalog.firstA1GuidedLessonId,
      );
      expect(
        plan.sessions[4].targetPhrases,
        SpeakingCourseCatalog.firstA1GuidedLesson.lines
            .map((line) => line.french)
            .toList(),
      );
      expect(plan.sessions.skip(5).first.unitTitle, isNotEmpty);
      expect(plan.sessions.skip(5).first.title, isNot(contains('Meetings')));
      // Unit 2's skills are fixed by position (vocabulary, speaking,
      // reading, listening, writing); only listening still needs its
      // durable audio track attached server-side.
      final unitTwo = plan.sessions.skip(5).toList(growable: false);
      expect(unitTwo.map((s) => s.primarySkill), [
        SpeakSkill.vocabulary,
        SpeakSkill.speaking,
        SpeakSkill.reading,
        SpeakSkill.listening,
        SpeakSkill.writing,
      ]);
      expect(
        unitTwo
            .where((s) => s.primarySkill != SpeakSkill.listening)
            .every((s) => s.isContentReady),
        isTrue,
      );
      expect(
        unitTwo
            .firstWhere((s) => s.primarySkill == SpeakSkill.listening)
            .isContentReady,
        isFalse,
      );
      final personalizedTitles = unitTwo
          .map((session) => session.title.toLowerCase())
          .toList(growable: false);
      expect(personalizedTitles.toSet(), hasLength(5));
      expect(personalizedTitles, isNot(contains('introduce yourself')));
      expect(
        personalizedTitles,
        isNot(contains('introduce yourself naturally')),
      );
    },
  );

  test(
    'onboarding interests no longer change the fixed per-unit skill order',
    () {
      // The learner's interests still choose the situation/context, but the
      // order of skills within a personalized unit is fixed: vocabulary,
      // then speaking, reading, listening, writing — regardless of which
      // interests were selected during onboarding.
      final store = AdaptiveCourseStore(sqlite3.openInMemory());
      final plan = store.ensureCurrentPlan(
        Profile(
          id: 'listener',
          goal: 'everyday',
          level: 'a2',
          interests: const ['Listening'],
        ),
      );

      final personalized = plan.sessions.skip(5).toList(growable: false);
      expect(personalized, hasLength(5));
      expect(personalized.first.primarySkill, SpeakSkill.vocabulary);
      expect(
        plan.sessions.take(4).map((session) => session.primarySkill),
        everyElement(SpeakSkill.alphabet),
      );
      expect(plan.sessions[4].title, 'Introduce yourself');
      expect(
        personalized.every(
          (session) => !session.title.toLowerCase().contains('introduc'),
        ),
        isTrue,
      );
    },
  );

  test('session five is authored and session six is new at every level', () {
    for (final level in ['a1', 'a2', 'b1', 'b2']) {
      final store = AdaptiveCourseStore(sqlite3.openInMemory());
      final plan = store.ensureCurrentPlan(
        Profile(id: 'learner-$level', goal: 'everyday', level: level),
      );

      expect(
        plan.sessions.take(4).map((session) => session.primarySkill),
        everyElement(SpeakSkill.alphabet),
      );
      expect(plan.sessions[4].title, 'Introduce yourself');
      expect(
        plan.sessions[4].contentKey,
        SpeakingCourseCatalog.firstA1GuidedLessonId,
      );
      expect(plan.sessions[5].title.toLowerCase(), isNot(contains('introduc')));
      if (level == 'a1') {
        expect(plan.sessions[5].title, isNot('Say hello'));
        expect(plan.sessions[5].targetPhrases, isNot(contains('bonjour')));
        expect(plan.sessions[5].targetPhrases, isNot(contains('je m’appelle')));
      }
    }
  });

  test('guided speaking cache rejects instruction prefixes and duplicate cards', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(
      id: 'guided-cache-contract',
      goal: 'everyday',
      level: 'a1',
    );
    // Speaking is the second personalized row (after vocabulary); mark the
    // vocabulary row ready first so the store grows to it.
    var plan = store.ensureCurrentPlan(profile);
    while (!plan.sessions.any(
      (session) => !session.isFoundation && session.primarySkill == SpeakSkill.speaking,
    )) {
      _finishSession(db, store, plan.sessions.last);
      plan = store.ensureCurrentPlan(profile);
    }
    final speaking = plan.sessions.firstWhere(
      (session) =>
          !session.isFoundation &&
          session.primarySkill == SpeakSkill.speaking &&
          session.status != 'completed',
    );
    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      'artifact_json = ? WHERE id = ?',
      [
        '{"practiceMode":"guidedConversation","lines":['
        '{"fr":"Répétez : bonjour.","en":"Repeat hello."},'
        '{"fr":"Bonjour.","en":"Hello."},'
        '{"fr":"Bonjour.","en":"Hello."}]}',
        speaking.id,
      ],
    );
    expect(store.sessionById(speaking.id)!.isContentReady, isFalse);
  });

  test('Course planner never assigns Free Talk or Roleplay speaking modes', () {
    final sessions = AdaptiveCoursePlanGenerator.generate(
      profile: Profile(
        id: 'guided-course-speaking',
        goal: 'everyday',
        level: 'a1',
        interests: const ['Speaking'],
      ),
      planId: 'guided-course-plan',
      profileFingerprint: 'everyday|A1|10|speaking',
      startSequence: 1,
      count: 15,
    );

    expect(
      sessions
          .skip(adaptiveCourseFoundationSize)
          .every(
            (session) =>
                session.primarySkill != SpeakSkill.freeTalk &&
                session.primarySkill != SpeakSkill.roleplay,
          ),
      isTrue,
    );
    expect(
      sessions
          .skip(adaptiveCourseFoundationSize)
          .where((session) => session.primarySkill == SpeakSkill.speaking)
          .every((session) => session.practiceMode == 'guidedConversation'),
      isTrue,
    );
  });

  test('reserve adds one row only after the previous artifact is ready', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final profile = Profile(
      id: 'serial-reserve',
      goal: 'everyday',
      level: 'a1',
      interests: const ['Speaking'],
    );
    // Foundation and Unit 2 (sequences 1-10) are authored, not generated, and
    // all exist from the first call — no simulated server completion is
    // needed for them. Complete all of Unit 2 (including the still-unready
    // listening lesson, which a real learner only reaches once its audio is
    // attached) so this test can focus on the ordinary AI-personalized
    // reserve rule that starts at sequence 11.
    final plan = store.ensureCurrentPlan(profile);
    for (final session in plan.sessions) {
      store.markCompleted(session.contentKey);
    }
    final first = store.ensureCurrentPlan(profile);
    expect(first.sessions.last.sequence, 11);
    expect(first.sessions.last.generationStatus, 'queued');

    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      "artifact_kind = 'speaking', artifact_json = ? WHERE id = ?",
      [_readyArtifactFor(first.sessions.last.primarySkill), first.sessions.last.id],
    );

    final second = store.ensureCurrentPlan(profile);
    expect(second.sessions.last.sequence, 12);
    expect(second.sessions.last.generationStatus, 'queued');
    expect(store.ensureCurrentPlan(profile).sessions.last.sequence, 12);

    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      "artifact_kind = 'speaking', artifact_json = ? WHERE id = ?",
      [_readyArtifactFor(second.sessions.last.primarySkill), second.sessions.last.id],
    );
    expect(store.ensureCurrentPlan(profile).sessions.last.sequence, 12);

    store.markCompleted(first.sessions.last.contentKey);
    final replenished = store.ensureCurrentPlan(profile);
    expect(replenished.sessions.last.sequence, 13);
    expect(replenished.sessions.last.generationStatus, 'queued');
  });

  test(
    'the first two personalized batches stay in a small CEFR practice lane',
    () {
      for (final level in ['a1', 'a2', 'b1', 'b2']) {
        final store = AdaptiveCourseStore(sqlite3.openInMemory());
        final profile = Profile(
          id: 'early-$level',
          goal: 'everyday',
          level: level,
          interests: const [
            'Speaking',
            'Listening',
            'Reading',
            'Writing',
            'Grammar',
            'Vocabulary',
          ],
        );
        var expanded = store.ensureCurrentPlan(profile);
        for (var index = 0; index < 4; index++) {
          store.markCompleted(expanded.sessions.last.contentKey);
          expanded = store.ensureCurrentPlan(profile);
        }
        final early = expanded.sessions.skip(5).take(5).toList();

        expect(early, hasLength(5));
        expect(
          early.every(
            (session) => session.contextPrompt.contains('early guided phase'),
          ),
          isTrue,
        );
        if (level == 'a1') {
          expect(
            early.every(
              (session) =>
                  !session.competency.toLowerCase().contains('condition') &&
                  !session.grammarFocus.any(
                    (value) => value.toLowerCase().contains('condition'),
                  ),
            ),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'upgrades an old generated session five to the authored speaking lesson',
    () {
      final db = sqlite3.openInMemory();
      final store = AdaptiveCourseStore(db);
      final profile = Profile(id: 'learner', goal: 'everyday', level: 'a1');
      final first = store.ensureCurrentPlan(profile);
      db.execute(
        '''UPDATE adaptive_course_sessions
         SET title = 'Connect sound to meaning', primary_skill = 'vocabulary',
             content_key = 'adaptive_old_s005', generation_status = 'ready',
             artifact_kind = 'vocabulary', artifact_json = '{}'
         WHERE id = ?''',
        [first.sessions[4].id],
      );

      final repaired = store.ensureCurrentPlan(profile);
      final session = repaired.sessions[4];
      expect(session.title, 'Introduce yourself');
      expect(session.primarySkill, SpeakSkill.speaking);
      expect(session.contentKey, SpeakingCourseCatalog.firstA1GuidedLessonId);
      expect(session.generationStatus, 'ready');
      expect(session.artifact, isNull);
    },
  );

  test('Course keeps growing one row at a time past the old five-lesson block', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    var plan = store.ensureCurrentPlan(profile);
    // Foundation (1-5) and Unit 2 (6-10) are both authored and fully present
    // immediately.
    expect(plan.sessions, hasLength(10));

    // Complete all of Unit 2, as a learner would; real AI-personalized
    // growth (sequence 11+) only begins once it is out of the way.
    for (final session in plan.sessions) {
      store.markCompleted(session.contentKey);
    }
    plan = store.ensureCurrentPlan(profile);
    expect(plan.sessions, hasLength(11));
    expect(plan.sessions.last.sequence, 11);
    expect(plan.sessions.last.blockIndex, 2);
    expect(plan.sessions.last.blockPosition, 1);

    // The personalized route beyond Unit 2 is unlimited: keep completing the
    // newest lesson and asking for the next one. It must keep growing one
    // row at a time instead of stopping.
    for (var total = 12; total <= 15; total++) {
      store.markCompleted(plan.sessions.last.contentKey);
      plan = store.ensureCurrentPlan(profile);
      expect(plan.sessions, hasLength(total));
    }
    expect(plan.sessions.last.sequence, 15);
  });

  test('personalized batches keep a useful transfer balance', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(
      id: 'listener',
      goal: 'everyday',
      level: 'b1',
      interests: const ['Listening'],
    );
    var expanded = store.ensureCurrentPlan(profile);
    for (var index = 0; index < 4; index++) {
      store.markCompleted(expanded.sessions.last.contentKey);
      expanded = store.ensureCurrentPlan(profile);
    }
    final firstBatch = expanded.sessions.skip(5).take(5);

    expect(
      firstBatch.any((session) => session.primarySkill == SpeakSkill.speaking),
      isTrue,
    );
    expect(
      firstBatch.any(
        (session) => session.primarySkill == SpeakSkill.vocabulary,
      ),
      isTrue,
    );

    expect(firstBatch, hasLength(5));
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
    // Foundation and all of authored Unit 2 already exist from the first
    // call. Unit 2 is fixed, authored content, not part of the "keep two
    // ready ahead" reserve, so it never blocks growth into real
    // AI-personalized territory (sequence 11+) — this call grows one more
    // row immediately, regardless of Unit 2's own completion state.
    expect(after.sessions, hasLength(11));
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
