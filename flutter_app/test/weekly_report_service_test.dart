import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' hide Session;
import 'package:sqlite3/sqlite3.dart' hide Session;

import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/data/database/storage_service.dart';
import 'package:french_tutor/data/database/vocabulary_session_store.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/models/session.dart';
import 'package:french_tutor/services/weekly_report_service.dart';

void main() {
  late CommonDatabase db;
  late LearningStore learning;
  late StorageService storage;
  late VocabularySessionStore vocabulary;

  setUp(() {
    db = sqlite3.openInMemory();
    learning = LearningStore(db);
    storage = StorageService(db);
    vocabulary = VocabularySessionStore(db);
  });

  tearDown(() => db.dispose());

  test(
    'empty week is empty and report reads do not create a daily session',
    () {
      final now = DateTime.now();
      final report = WeeklyReportService(
        learning: learning,
        storage: storage,
        vocabularySessions: vocabulary,
      ).compute(now: now);

      expect(report.hasActivity, isFalse);
      expect(report.activeDays, 0);
      expect(report.sessions, isEmpty);
      expect(learning.existingDailySession(on: now), isNull);
    },
  );

  test(
    'week summary uses saved sessions, vocabulary and writing corrections',
    () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final sessionStart = today.add(const Duration(hours: 9));
      final sessionEnd = sessionStart.add(const Duration(minutes: 12));

      storage.saveSession(
        Session(
          id: 'speaking-this-week',
          startedAt: sessionStart.toIso8601String(),
          endedAt: sessionEnd.toIso8601String(),
          stage: 'speaking',
        ),
      );
      storage.saveMessage(
        sessionId: 'speaking-this-week',
        role: 'user',
        content: 'Je vais au marché demain.',
      );

      final market = VocabEntry(
        id: 'market',
        en: 'market',
        fr: 'marché',
        phonetic: 'mar-shay',
      );
      vocabulary.create(
        id: 'vocab-this-week',
        title: 'Weekly words',
        source: 'weekly-review',
        topic: 'Market',
        levelBand: 'A1',
        entries: [market],
      );
      vocabulary.saveProgress(
        id: 'vocab-this-week',
        currentStep: 'complete',
        currentIndex: 1,
        recallGrades: {'market': 'correct'},
        contextResults: const {},
        sentenceResults: const {},
        contextExamples: const {},
      );

      learning.saveSubmission(
        taskId: 'writing-this-week',
        text: 'Je suis travailler demain.',
        feedback: jsonEncode({
          'corrections': [
            {
              'original': 'Je suis travailler demain.',
              'fixed': 'Je vais travailler demain.',
              'why': 'Use aller + infinitive for a near-future plan.',
            },
          ],
        }),
      );

      final report = WeeklyReportService(
        learning: learning,
        storage: storage,
        vocabularySessions: vocabulary,
      ).compute(now: now);

      expect(report.hasActivity, isTrue);
      expect(report.activeDays, 1);
      expect(report.sessions, hasLength(1));
      expect(report.practiceMinutes, 12);
      expect(report.speakingSessions, 1);
      expect(report.speakingTurns, 1);
      expect(report.latestLearnerLine, 'Je vais au marché demain.');
      expect(report.words, hasLength(1));
      expect(report.words.single.entry.fr, 'marché');
      expect(report.words.single.wasRecalled, isTrue);
      expect(report.corrections, hasLength(1));
      expect(report.corrections.single.corrected, 'Je vais travailler demain.');
    },
  );

  test('sessions outside the selected week are excluded', () {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final outsideStart = monday.subtract(const Duration(days: 2));
    final outsideEnd = outsideStart.add(const Duration(minutes: 8));
    storage.saveSession(
      Session(
        id: 'last-week',
        startedAt: outsideStart.toIso8601String(),
        endedAt: outsideEnd.toIso8601String(),
        stage: 'speaking',
      ),
    );

    final report = WeeklyReportService(
      learning: learning,
      storage: storage,
      vocabularySessions: vocabulary,
    ).compute(now: now);

    expect(report.sessions, isEmpty);
    expect(report.activeDays, 0);
  });

  test('a completed vocabulary practice marks its day as active', () {
    final entry = VocabEntry(
      id: 'bonjour',
      en: 'hello',
      fr: 'bonjour',
      phonetic: 'bohn-zhoor',
    );
    vocabulary.create(
      id: 'vocab-only',
      title: 'Greetings',
      source: 'weekly-review',
      topic: 'Greetings',
      levelBand: 'A1',
      entries: [entry],
    );
    vocabulary.saveProgress(
      id: 'vocab-only',
      currentStep: 'recall',
      currentIndex: 1,
      recallGrades: {'bonjour': 'correct'},
      contextResults: const {},
      sentenceResults: const {},
      contextExamples: const {},
    );

    final report = WeeklyReportService(
      learning: learning,
      storage: storage,
      vocabularySessions: vocabulary,
    ).compute();

    expect(report.activeDays, 1);
    expect(report.words.single.entry.fr, 'bonjour');
  });
}
