import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/models/speaking_course.dart';

void main() {
  test('listening stays unready until its durable PCM WAV is attached', () {
    final db = sqlite3.openInMemory();
    final store = AdaptiveCourseStore(db);
    final plan = store.ensureCurrentPlan(
      Profile(
        id: 'listener-ready-contract',
        goal: 'everyday',
        level: 'a1',
        interests: const ['Listening'],
      ),
    );
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
    final plan = store.ensureCurrentPlan(
      Profile(
        id: 'a1-content-contract',
        goal: 'everyday',
        level: 'a1',
        interests: const ['Speaking'],
      ),
    );
    final speaking = plan.sessions.firstWhere(
      (session) =>
          !session.isFoundation && session.primarySkill == SpeakSkill.speaking,
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
    'fresh learner gets five foundations and one personalized specification',
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

      expect(plan.sessions, hasLength(6));
      expect(
        plan.sessions.map((session) => session.contentKey).toSet(),
        hasLength(6),
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
      expect(
        plan.sessions.take(5).every((session) => session.isContentReady),
        isTrue,
      );
      expect(
        plan.sessions.skip(5).every((session) => !session.isContentReady),
        isTrue,
      );
      final personalizedTitles = plan.sessions
          .skip(5)
          .map((session) => session.title.toLowerCase())
          .toList(growable: false);
      expect(personalizedTitles.toSet(), hasLength(1));
      expect(personalizedTitles, isNot(contains('introduce yourself')));
      expect(
        personalizedTitles,
        isNot(contains('introduce yourself naturally')),
      );
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

      final personalized = plan.sessions.skip(5).toList(growable: false);
      expect(
        personalized
            .take(3)
            .every((session) => session.primarySkill == SpeakSkill.listening),
        isTrue,
      );
      expect(personalized, hasLength(1));
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
    final plan = store.ensureCurrentPlan(
      Profile(id: 'guided-cache-contract', goal: 'everyday', level: 'a1'),
    );
    final speaking = plan.sessions.firstWhere(
      (session) =>
          !session.isFoundation && session.primarySkill == SpeakSkill.speaking,
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
    final first = store.ensureCurrentPlan(profile);
    expect(first.sessions, hasLength(6));

    const readySpeaking =
        '{"practiceMode":"guidedConversation","lines":['
        '{"fr":"Bonjour.","en":"Hello."},'
        '{"fr":"Je m’appelle Léa.","en":"My name is Lea."},'
        '{"fr":"Merci.","en":"Thank you."}]}';
    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      "artifact_kind = 'speaking', artifact_json = ? WHERE id = ?",
      [readySpeaking, first.sessions.last.id],
    );

    final second = store.ensureCurrentPlan(profile);
    expect(second.sessions, hasLength(7));
    expect(second.sessions.last.generationStatus, 'queued');
    expect(store.ensureCurrentPlan(profile).sessions, hasLength(7));

    db.execute(
      "UPDATE adaptive_course_sessions SET generation_status = 'ready', "
      "artifact_kind = 'speaking', artifact_json = ? WHERE id = ?",
      [readySpeaking, second.sessions.last.id],
    );
    expect(store.ensureCurrentPlan(profile).sessions, hasLength(7));

    store.markCompleted(second.sessions[5].contentKey);
    final replenished = store.ensureCurrentPlan(profile);
    expect(replenished.sessions, hasLength(8));
    expect(replenished.sessions.last.sequence, 8);
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

  test('Unit 2 grows one row at a time and stops at five lessons', () {
    final store = AdaptiveCourseStore(sqlite3.openInMemory());
    final profile = Profile(id: 'learner', goal: 'everyday', level: 'a2');
    var plan = store.ensureCurrentPlan(profile);
    expect(plan.sessions, hasLength(6));

    for (
      var personalizedCount = 2;
      personalizedCount <= 5;
      personalizedCount++
    ) {
      store.markCompleted(plan.sessions.last.contentKey);
      plan = store.ensureCurrentPlan(profile);
      expect(
        plan.sessions,
        hasLength(adaptiveCourseFoundationSize + personalizedCount),
      );
    }

    store.markCompleted(plan.sessions.last.contentKey);
    final capped = store.ensureCurrentPlan(profile);
    expect(capped.sessions, hasLength(10));
    expect(capped.sessions.last.sequence, 10);
    expect(capped.sessions.last.blockIndex, 1);
    expect(capped.sessions.last.blockPosition, adaptiveCourseBatchSize);
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
    expect(after.sessions, hasLength(6));
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
