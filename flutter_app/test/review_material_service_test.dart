import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/storage_service.dart';
import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/data/database/review_store.dart';
import 'package:french_tutor/models/session.dart';
import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/services/review_material_service.dart';
import 'package:french_tutor/services/review_context_cache_service.dart';
import 'package:french_tutor/services/session_recorder.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

void main() {
  test(
    'dedicated Course vocabulary/listening sessions reach review history',
    () {
      final storage = StorageService(sqlite3.openInMemory());
      storage.saveSession(
        Session(
          id: 'course-vocabulary',
          startedAt: '2026-09-09T09:00:00.000Z',
          endedAt: '2026-09-09T09:05:00.000Z',
          summary: 'Completed the course session: Learn people words',
          topic: 'Learn people words',
          contentKey: 'course-vocabulary-key',
          stage: 'vocabulary',
        ),
      );
      storage.saveSession(
        Session(
          id: 'course-listening',
          startedAt: '2026-09-09T09:06:00.000Z',
          endedAt: '2026-09-09T09:11:00.000Z',
          summary: 'Completed the course session: Hear a name',
          topic: 'Hear a name',
          contentKey: 'course-listening-key',
          stage: 'listening',
        ),
      );

      final recent = ReviewMaterialService.recentSessions(storage);

      expect(recent.map((item) => item.skill), ['Listening', 'Vocabulary']);
      expect(SessionRecorder.tagForStage('vocabulary'), 'Vocabulary');
      expect(SessionRecorder.tagForStage('listening'), 'Listening');
    },
  );

  test('course transcript recorder preserves the artifact join key', () {
    final storage = StorageService(sqlite3.openInMemory());
    final recorder = SessionRecorder(
      storage: storage,
      stage: 'speaking_guided',
      topic: 'Say what you like',
      contentKey: 'unit-3-speaking-1',
    );
    recorder.logUser('Je veux travailler.');
    recorder.logTutor('Target: Je veux travailler.');
    recorder.finish(summary: 'Completed a speaking step.');

    final saved = storage.getAllSessions().single;
    expect(saved.contentKey, 'unit-3-speaking-1');
    expect(saved.stage, 'speaking_guided');
    expect(storage.getSessionMessages(sessionId: saved.id), hasLength(2));
  });

  test('all speaking stage variants appear in recent speaking history', () {
    final storage = StorageService(sqlite3.openInMemory());
    final stages = [
      'speaking_guided',
      'picture_description',
      'pronunciation_repair',
    ];

    for (var index = 0; index < stages.length; index++) {
      final id = 'speaking-$index';
      storage.saveSession(
        Session(
          id: id,
          startedAt: '2026-08-22T09:0$index:00.000Z',
          endedAt: '2026-08-22T09:1$index:00.000Z',
          summary: 'Completed speaking practice.',
          topic: 'Topic $index',
          stage: stages[index],
        ),
      );
      storage.saveMessage(
        sessionId: id,
        role: 'assistant',
        content: 'Bonjour.',
      );
    }

    final recent = ReviewMaterialService.recentSessions(storage);

    expect(recent, hasLength(3));
    expect(recent.map((session) => session.skill), everyElement('Speaking'));
    expect(
      recent.map((session) => session.sessionId),
      containsAll(<String>['speaking-0', 'speaking-1', 'speaking-2']),
    );
    expect(recent.first.details, contains('Tutor: Bonjour.'));
    expect(storage.getSessionMessages(sessionId: 'speaking-0'), hasLength(1));
  });

  test('review ledger freezes targets and attempt state', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = ReviewStore(db);
    final planId = store.createPlan(
      kind: 'review',
      requestedMode: 'smart',
      resolvedMode: 'speaking',
      levelBand: 'A2',
      goal: 'everyday',
      durationMinutes: 10,
      topic: 'Housing',
      sourceFingerprint: 'abc123',
      brief: {
        'targets': [
          {
            'key': 'target-1',
            'type': 'repair',
            'text': 'un bail',
            'reason': 'repeated mistake',
            'priority': 1.0,
            'sourceIds': ['session-1'],
          },
        ],
      },
    );
    final attemptId = store.startAttempt(planId: planId, mode: 'speaking');
    store.markGenerated(planId, {'activityId': 'activity-1'});
    store.completeAttempt(attemptId, sessionId: 'session-2');

    expect(store.planById(planId)?.status, 'generated');
    expect(store.planById(planId)?.brief['targets'], isNotEmpty);
    expect(store.attemptsForPlan(planId).single.status, 'completed');
    expect(store.attemptsForPlan(planId).single.sessionId, 'session-2');
    expect(
      db
          .select('SELECT COUNT(*) AS count FROM review_plan_targets')
          .single['count'],
      1,
    );
  });

  test('warm-up keeps a bounded recent-plus-upcoming Course window', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final profile = Profile(
      id: 'warmup-profile',
      level: 'a1',
      goal: 'everyday',
      interests: const ['Travel'],
    );
    final course = AdaptiveCourseStore(db);
    final coursePlan = course.ensureCurrentPlan(profile);
    db.execute(
      '''UPDATE adaptive_course_sessions
         SET status = 'completed', completed_at = ?, updated_at = ?
         WHERE id = ?''',
      [
        '2026-09-08T12:00:00.000Z',
        '2026-09-08T12:00:00.000Z',
        coursePlan.sessions.first.id,
      ],
    );

    final plan = ReviewMaterialService.buildWarmupPlan(
      db: db,
      profile: profile,
      mode: 'smart',
    );

    expect(plan.kind, 'warmup');
    expect(plan.futureSessionId, isNotNull);
    expect(plan.futureSessionIds, hasLength(3));
    expect(plan.futureLessonSummaries, hasLength(3));
    expect(plan.futureContext, contains('RECENT COMPLETED COURSE MATERIAL'));
    expect(plan.futureContext, contains('UPCOMING COURSE WINDOW'));
    expect(plan.briefJson['futureSessionIds'], hasLength(3));
    expect(plan.contextPrompt, contains('WARM-UP DIRECTION'));
    expect(plan.targets, isNotEmpty);
  });

  test(
    'review plan, generated payload, targets, and attempts restore locally',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final store = ReviewStore(db);
      const planId = '00000000-0000-4000-8000-000000000001';
      const targetId = '00000000-0000-4000-8000-000000000002';
      const attemptId = '00000000-0000-4000-8000-000000000003';
      const timestamp = '2026-09-09T12:00:00.000Z';
      store.upsertPlanFromRemote({
        'id': planId,
        'user_id': 'user-1',
        'kind': 'warmup',
        'requested_mode': 'smart',
        'resolved_mode': 'reading',
        'level_band': 'A1',
        'goal': 'everyday',
        'duration_minutes': 5,
        'topic': 'At work',
        'source_fingerprint': 'fingerprint',
        'brief_json': {
          'futureSessionIds': ['lesson-1', 'lesson-2'],
        },
        'generated_json': {'activityId': 'activity-1'},
        'status': 'generated',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      store.upsertTargetFromRemote({
        'id': targetId,
        'plan_id': planId,
        'target_key': 'phrase-1',
        'target_type': 'future_phrase',
        'display_text': 'au bureau',
        'reason': 'upcoming lesson target',
        'priority': .9,
        'source_ids_json': ['lesson-1'],
        'evidence_json': {'lesson': 'lesson-1'},
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      store.upsertAttemptFromRemote({
        'id': attemptId,
        'user_id': 'user-1',
        'plan_id': planId,
        'mode': 'reading',
        'status': 'completed',
        'started_at': timestamp,
        'completed_at': timestamp,
        'created_at': timestamp,
        'updated_at': timestamp,
        'result_json': {'score': 1},
      });

      expect(store.planById(planId)?.generated['activityId'], 'activity-1');
      expect(store.planById(planId)?.brief['futureSessionIds'], hasLength(2));
      expect(store.attemptsForPlan(planId).single.status, 'completed');
      expect(
        db
            .select('SELECT display_text FROM review_plan_targets')
            .single['display_text'],
        'au bureau',
      );
    },
  );

  test('review context cache is rebuildable and keeps recent evidence', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final storage = StorageService(db);
    storage.saveSession(
      Session(
        id: 'cached-session',
        startedAt: '2026-09-04T10:00:00.000Z',
        endedAt: '2026-09-04T10:10:00.000Z',
        summary: 'Practised a café request.',
        topic: 'Café',
        stage: 'speaking',
      ),
    );
    storage.saveMessage(
      sessionId: 'cached-session',
      role: 'user',
      content: 'Je voudrais un café, s’il vous plaît.',
    );

    ReviewContextCacheService.rebuildNow(db);
    final cache = ReviewContextCacheService.read(db);

    expect(cache, isNotNull);
    expect(cache!['recentTopics'], contains('Café'));
    expect(
      cache['transcriptExcerpts'],
      contains('Je voudrais un café, s’il vous plaît.'),
    );
  });

  test('recent Course sessions expose their generated activity', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final profile = Profile(
      id: 'course-review-profile',
      level: 'a1',
      goal: 'everyday',
    );
    final course = AdaptiveCourseStore(db);
    final plan = course.ensureCurrentPlan(profile);
    final lesson = plan.sessions.first;
    db.execute(
      '''UPDATE adaptive_course_sessions
         SET artifact_json = ?, generation_status = 'ready', status = 'completed',
             completed_at = ?, updated_at = ?
         WHERE content_key = ?''',
      [
        '{"prompt":"Je ___ au bureau.","choices":["suis","est"]}',
        '2026-09-05T10:10:00.000Z',
        '2026-09-05T10:10:00.000Z',
        lesson.contentKey,
      ],
    );
    final storage = StorageService(db);
    storage.saveSession(
      Session(
        id: 'course-review-session',
        startedAt: '2026-09-05T10:00:00.000Z',
        endedAt: '2026-09-05T10:10:00.000Z',
        summary: 'Completed the course session: ${lesson.title}',
        topic: lesson.title,
        contentKey: lesson.contentKey,
        stage: lesson.primarySkill.wireName,
      ),
    );

    final recent = ReviewMaterialService.recentSessions(storage);

    expect(recent, isNotEmpty);
    expect(recent.first.details, contains(startsWith('Generated activity:')));
    expect(recent.first.displaySummary, startsWith('Lesson:'));
  });

  test(
    'course completion keeps a bounded artifact fallback when the join is late',
    () {
      final storage = StorageService(sqlite3.openInMemory());
      storage.markCourseSessionCompleted(
        contentKey: 'course-fallback',
        topic: 'Build a short sentence',
        stage: 'grammar',
        lessonMaterial:
            'Lesson: Build a short sentence\n'
            'Generated activity: ${'x' * 3000}',
      );

      final saved = storage.getAllSessions().single;
      final messages = storage.getSessionMessages(sessionId: saved.id);
      expect(messages, hasLength(1));
      expect(messages.single.content, startsWith('Course lesson material:'));
      expect(messages.single.content.length, lessThanOrEqualTo(1824));
    },
  );
}
