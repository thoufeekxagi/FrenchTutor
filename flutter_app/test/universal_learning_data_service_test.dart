import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Session;

import 'package:french_tutor/data/database/adaptive_course_store.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/data/database/storage_service.dart';
import 'package:french_tutor/models/session.dart';
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
    final plan = store.ensureCurrentPlan(profile);
    final first = plan.sessions.first;
    final reloaded = store.sessionById(first.id);

    expect(plan.sessions, hasLength(20));
    expect(first.context, contains('recent work'));
    expect(first.targetPhrases, contains('Je travaille dans le marketing'));
    expect(first.sourceSessionIds, contains('practice-source'));
    expect(reloaded?.targetPhrases, contains('Je travaille dans le marketing'));
    expect(reloaded?.sourceSessionIds, contains('practice-source'));
  });
}
