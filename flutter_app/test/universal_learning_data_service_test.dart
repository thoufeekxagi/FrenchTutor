import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Session;

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/data/database/storage_service.dart';
import 'package:french_tutor/models/session.dart';
import 'package:french_tutor/services/review_material_service.dart';
import 'package:french_tutor/services/universal_learning_data_service.dart';

void main() {
  test('snapshot combines Course, Practice, Live, writing, and mistakes', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    final learning = LearningStore(db);
    final profile = learning.profile()
      ..goal = 'everyday'
      ..level = 'a2'
      ..interests = ['speaking'];
    learning.saveProfile(profile);

    final storage = StorageService(db);
    final courseSession = Session(
      id: 'course-session',
      startedAt: '2026-09-01T10:00:00.000Z',
      endedAt: '2026-09-01T10:10:00.000Z',
      summary: 'Practised housing vocabulary and polite requests.',
      topic: 'Housing',
      contentKey: 'adaptive_plan_s001',
      stage: 'writing',
      vocabulary: ['Je voudrais visiter l’appartement', 'un bail'],
    );
    storage.saveSession(courseSession);
    storage.saveMessage(
      sessionId: courseSession.id,
      role: 'user',
      content: 'Je cherche un appartement à Montréal.',
    );
    learning.setLessonStatus('reading-housing', 'completed', score: 0.6);

    final practiceSession = Session(
      id: 'practice-session',
      startedAt: '2026-09-02T10:00:00.000Z',
      endedAt: '2026-09-02T10:10:00.000Z',
      summary: 'Practised asking for clarification.',
      topic: 'Conversation',
      stage: 'speaking',
    );
    storage.saveSession(practiceSession);

    final aiSession = learning.startAiSession(
      stage: 'speaking',
      topic: 'Housing roleplay',
    );
    learning.endAiSession(
      aiSession,
      endedReason: 'completed',
      learnerUtteranceCount: 2,
      transcriptJson: jsonEncode([
        {'role': 'user', 'content': 'Pouvez-vous répéter, s’il vous plaît ?'},
        {'role': 'assistant', 'content': 'Bien sûr.'},
      ]),
    );
    learning.saveSubmission(
      taskId: 'housing-message',
      text: 'Je voudrais visiter l’appartement demain.',
      feedback: 'Correct the article agreement in one phrase.',
    );
    learning.logMistake(
      tag: 'article-agreement',
      description: 'Review masculine and feminine housing nouns.',
    );

    final snapshot = UniversalLearningDataService.buildSnapshot(db, profile);

    expect(snapshot.courseSessionCount, 1);
    expect(snapshot.practiceSessionCount, 1);
    expect(snapshot.recentTopics, contains('Housing'));
    expect(
      snapshot.transcriptExcerpts,
      contains('Pouvez-vous répéter, s’il vous plaît ?'),
    );
    expect(snapshot.writingSignals, isNotEmpty);
    expect(
      snapshot.performanceSignals,
      contains('lesson reading-housing: completed, score 0.6'),
    );
    expect(
      snapshot.repeatedMistakes,
      contains(
        'article-agreement: Review masculine and feminine housing nouns.',
      ),
    );
    expect(
      snapshot.targetPhrases,
      contains('Je cherche un appartement à Montréal'),
    );
    expect(snapshot.compactContext, contains('Housing'));
    expect(snapshot.compactContext, contains('Practice results'));
  });

  test('adaptive Course session stores learner targets and source ids', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    final learning = LearningStore(db);
    final profile = learning.profile()
      ..goal = 'everyday'
      ..level = 'a2';
    learning.saveProfile(profile);

    final storage = StorageService(db);
    storage.saveSession(
      Session(
        id: 'practice-source',
        startedAt: '2026-09-02T10:00:00.000Z',
        endedAt: '2026-09-02T10:10:00.000Z',
        summary: 'Practised work introductions.',
        topic: 'Work',
        stage: 'speaking',
        vocabulary: ['Je travaille dans le marketing'],
      ),
    );

    final store = AdaptiveCourseStore(db);
    var plan = store.ensureCurrentPlan(profile);
    // Sequences 1-5 (foundation) and 6-11 (Unit 2) are both fixed, authored
    // content shared by every learner, so recent evidence cannot show up
    // there. The first lesson that can actually carry this evidence is the
    // first real AI-personalized one, sequence 12 — complete Unit 2 first
    // so the store grows to it.
    for (final session in plan.sessions) {
      store.markCompleted(session.contentKey);
    }
    plan = store.ensureCurrentPlan(profile);
    final first =
        plan.sessions[adaptiveCourseFoundationSize + adaptiveCourseBatchSize];
    final reloaded = store.sessionById(first.id);

    expect(plan.sessions, hasLength(12));
    expect(first.context, contains('Unit 3 situation anchor'));
    expect(first.context, contains('Prior topics are retrieval evidence only'));
    expect(first.targetPhrases, contains('Je travaille dans le marketing'));
    expect(first.sourceSessionIds, contains('practice-source'));
    expect(reloaded?.targetPhrases, contains('Je travaille dans le marketing'));
    expect(reloaded?.sourceSessionIds, contains('practice-source'));
  });

  test(
    'Review plan prioritizes hard material and supports every output mode',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      final learning = LearningStore(db);
      final profile = learning.profile()
        ..goal = 'tef_canada'
        ..level = 'a2';
      learning.saveProfile(profile);

      final storage = StorageService(db);
      storage.saveSession(
        Session(
          id: 'review-source',
          startedAt: '2026-09-03T10:00:00.000Z',
          endedAt: '2026-09-03T10:10:00.000Z',
          summary: 'Practised asking for help at work.',
          topic: 'Work',
          stage: 'speaking',
          vocabulary: ['Je voudrais de l’aide'],
        ),
      );
      storage.saveMessage(
        sessionId: 'review-source',
        role: 'user',
        content: 'Je voudrais de l’aide, mais je cherche le bon mot.',
      );
      learning.saveSubmission(
        taskId: 'review-writing',
        text: 'Je voudrais demander de l’aide.',
        feedback: 'Check the article agreement in the next sentence.',
      );
      learning.logMistake(
        tag: 'article-agreement',
        description: 'Review masculine and feminine nouns.',
      );

      final plan = ReviewMaterialService.buildPersonalizedPlan(
        db: db,
        profile: profile,
        mode: 'writing',
      );

      expect(plan.mode, 'writing');
      expect(plan.levelBand, 'A2');
      expect(plan.topic, 'recent French writing targets');
      expect(
        plan.hardSignals,
        contains('article-agreement: Review masculine and feminine nouns.'),
      );
      expect(plan.retrievalTargets, contains('Je voudrais de l’aide'));
      expect(plan.sourceSessionIds, contains('review-source'));
      expect(plan.contextPrompt, contains('60% retrieval'));
      expect(plan.contextPrompt, contains('40% controlled novelty'));
      expect(plan.contextPrompt, contains('Learner transcript excerpts'));
      expect(plan.contextPrompt, contains('Writing evidence'));
    },
  );

  test('Review ignores unscoped SRS ids from outside recent sessions', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    final learning = LearningStore(db);
    final profile = learning.profile()..level = 'a2';
    learning.saveProfile(profile);
    final storage = StorageService(db);
    storage.saveSession(
      Session(
        id: 'recent-session',
        startedAt: '2026-09-07T10:00:00.000Z',
        endedAt: '2026-09-07T10:10:00.000Z',
        summary: 'Practised describing a change.',
        topic: 'Describing changes',
        stage: 'grammar',
      ),
    );

    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''INSERT INTO vocab_reviews
         (id, entry_id, grade, response_type, session_id, reviewed_at, created_at)
         VALUES (?, ?, ?, ?, NULL, ?, ?)''',
      ['old-review', 'at-the-cafe-word-3', 'again', 'flashcard', now, now],
    );
    db.execute(
      '''INSERT INTO vocab_cards
         (id, entry_id, ease, interval_days, reps, due_at, introduced_on,
          last_reviewed_at, last_grade, created_at, updated_at)
         VALUES (?, ?, 2.5, 0, 1, ?, ?, ?, ?, ?, ?)''',
      [
        'old-card',
        'at-the-cafe-word-3',
        now,
        '2026-09-01',
        now,
        'again',
        now,
        now,
      ],
    );

    final snapshot = UniversalLearningDataService.buildSnapshot(db, profile);

    expect(snapshot.vocabularySignals.join(' '), isNot(contains('cafe')));
    expect(snapshot.repeatedMistakes.join(' '), isNot(contains('cafe')));
    expect(snapshot.targetPhrases.join(' '), isNot(contains('cafe')));
  });
}
