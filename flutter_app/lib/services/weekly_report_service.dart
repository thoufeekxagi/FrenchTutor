import 'dart:convert';

import '../data/content_service.dart';
import '../data/database/learning_store.dart';
import '../data/database/storage_service.dart';
import '../data/database/vocabulary_session_store.dart';
import '../models/content_models.dart';
import '../models/daily_session.dart';
import '../models/session.dart';
import '../models/srs_state.dart';

class WeeklyReportDay {
  const WeeklyReportDay({
    required this.date,
    required this.isActive,
    required this.isFuture,
    required this.sessionCount,
  });

  final DateTime date;
  final bool isActive;
  final bool isFuture;
  final int sessionCount;
}

class WeeklyWordProgress {
  const WeeklyWordProgress({
    required this.entry,
    required this.practiceCount,
    required this.wasRecalled,
    required this.needsAnotherLook,
  });

  final VocabEntry entry;
  final int practiceCount;
  final bool wasRecalled;
  final bool needsAnotherLook;
}

class WeeklyCorrection {
  const WeeklyCorrection({
    required this.original,
    required this.corrected,
    required this.explanation,
    required this.submittedAt,
    required this.timesSeen,
  });

  final String original;
  final String corrected;
  final String explanation;
  final DateTime submittedAt;
  final int timesSeen;
}

class WeeklyReport {
  const WeeklyReport({
    required this.weekStart,
    required this.weekEndExclusive,
    required this.asOf,
    required this.days,
    required this.sessions,
    required this.skillSessionCounts,
    required this.words,
    required this.corrections,
    required this.activeDays,
    required this.practiceMinutes,
    required this.speakingTurns,
    required this.speakingSessions,
    required this.latestLearnerLine,
  });

  final DateTime weekStart;
  final DateTime weekEndExclusive;
  final DateTime asOf;
  final List<WeeklyReportDay> days;
  final List<Session> sessions;
  final Map<String, int> skillSessionCounts;
  final List<WeeklyWordProgress> words;
  final List<WeeklyCorrection> corrections;
  final int activeDays;
  final int practiceMinutes;
  final int speakingTurns;
  final int speakingSessions;
  final String? latestLearnerLine;

  bool get hasActivity =>
      activeDays > 0 ||
      sessions.isNotEmpty ||
      words.isNotEmpty ||
      corrections.isNotEmpty;

  int get recalledWords => words.where((word) => word.wasRecalled).length;
  int get wordsToRevisit => words.where((word) => word.needsAnotherLook).length;

  String? get mostPractisedSkill {
    if (skillSessionCounts.isEmpty) return null;
    return skillSessionCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }
}

/// Builds a calendar-week report from the learner's existing local records.
/// Those records already sync through the app's current infrastructure; this
/// service makes no API/LLM calls and writes nothing while reading history.
class WeeklyReportService {
  WeeklyReportService({
    required this.learning,
    required this.storage,
    required this.vocabularySessions,
    ContentService? content,
  }) : content = content ?? ContentService.shared;

  final LearningStore learning;
  final StorageService storage;
  final VocabularySessionStore vocabularySessions;
  final ContentService content;

  WeeklyReport compute({DateTime? now, int weekOffset = 0}) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final weekStart = currentMonday.add(Duration(days: weekOffset * 7));
    final weekEnd = weekStart.add(const Duration(days: 7));

    final sessions = storage
        .getAllSessions()
        .where((session) {
          final end = _date(session.endedAt);
          return end != null && _inRange(end.toLocal(), weekStart, weekEnd);
        })
        .toList(growable: false);

    final sessionsByDay = <String, int>{};
    final secondsByDay = <String, int>{};
    final skillCounts = <String, int>{};
    var speakingTurns = 0;
    var speakingSessions = 0;
    DateTime? latestSpeakingAt;
    String? latestLearnerLine;

    for (final session in sessions) {
      final endedAt = _date(session.endedAt)!.toLocal();
      final dayKey = _dayKey(endedAt);
      sessionsByDay.update(dayKey, (count) => count + 1, ifAbsent: () => 1);
      final startedAt = _date(session.startedAt)?.toLocal();
      if (startedAt != null) {
        final elapsed = endedAt.difference(startedAt);
        // Ignore nonsensical clock changes and screens left running all day.
        if (!elapsed.isNegative && elapsed <= const Duration(hours: 3)) {
          secondsByDay.update(
            dayKey,
            (seconds) => seconds + elapsed.inSeconds,
            ifAbsent: () => elapsed.inSeconds,
          );
        }
      }

      final skill = _skillFor(session.stage);
      if (skill != null) {
        skillCounts.update(skill, (count) => count + 1, ifAbsent: () => 1);
      }
      if (skill == 'Speaking') {
        speakingSessions++;
        try {
          final messages = storage.getSessionMessages(sessionId: session.id);
          speakingTurns += messages.where((message) => message.isUser).length;
          if (messages.isNotEmpty &&
              (latestSpeakingAt == null || endedAt.isAfter(latestSpeakingAt))) {
            final learnerMessages = messages
                .where(
                  (message) =>
                      message.isUser && message.content.trim().isNotEmpty,
                )
                .toList(growable: false);
            if (learnerMessages.isNotEmpty) {
              latestLearnerLine = _bounded(
                learnerMessages.last.content.trim(),
                180,
              );
              latestSpeakingAt = endedAt;
            }
          }
        } catch (_) {
          // One damaged legacy transcript should not hide the weekly report.
        }
      }
    }

    final wordData = <String, _WordAccumulator>{};
    final entriesById = <String, VocabEntry>{};
    for (final phase in content.vocabPhases) {
      for (final theme in phase.themes) {
        for (final entry in theme.entries) {
          entriesById[entry.id] = entry;
        }
      }
    }

    final weekReviews = learning.reviewsBetween(weekStart, weekEnd);
    for (final review in weekReviews) {
      final word = wordData.putIfAbsent(
        review.entryId,
        () => _WordAccumulator(review.entryId),
      );
      word.reviewEvents++;
      final reviewedAt = review.reviewedAt.toLocal();
      if (word.lastPractisedAt == null ||
          reviewedAt.isAfter(word.lastPractisedAt!)) {
        word.applyGrade(review.grade);
        word.lastPractisedAt = reviewedAt;
      }
    }

    final vocabularyActivityDays = <String>{};
    for (final vocabSession in vocabularySessions.startedBetween(
      weekStart,
      weekEnd,
    )) {
      for (final entry in vocabSession.entries) {
        entriesById[entry.id] = entry;
      }
      final practisedIds = <String>{
        ...vocabSession.recallGrades.keys,
        ...vocabSession.sentenceResults.keys,
      };
      if (practisedIds.isNotEmpty) {
        vocabularyActivityDays.add(_dayKey(vocabSession.startedAt.toLocal()));
      }
      for (final id in practisedIds) {
        final word = wordData.putIfAbsent(id, () => _WordAccumulator(id));
        word.vocabularySessionAttempts++;
        final grade = vocabSession.recallGrades[id];
        final practisedAt = vocabSession.updatedAt.toLocal();
        if (grade != null &&
            (word.lastPractisedAt == null ||
                !practisedAt.isBefore(word.lastPractisedAt!))) {
          if (grade == 'correct') {
            word.wasRecalled = true;
            word.needsAnotherLook = false;
          } else if (grade == 'attempted') {
            word.wasRecalled = false;
            word.needsAnotherLook = true;
          }
        }
        if (practisedAt.isAfter(
          word.lastPractisedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        )) {
          word.lastPractisedAt = practisedAt;
        }
      }
    }

    final activityDays = <String>{
      ...sessionsByDay.keys,
      ...vocabularyActivityDays,
    };
    var trackedHabitMinutes = <String, int>{};
    for (var index = 0; index < 7; index++) {
      final day = weekStart.add(Duration(days: index));
      if (day.isAfter(today)) continue;
      final key = _dayKey(day);
      try {
        final habits = learning.habits(on: day);
        final activeHabits = habits.values.where(
          (habit) => habit.done || habit.minutes > 0,
        );
        if (activeHabits.isNotEmpty) activityDays.add(key);
        trackedHabitMinutes[key] = activeHabits.fold<int>(
          0,
          (total, habit) => total + habit.minutes,
        );
      } catch (_) {
        trackedHabitMinutes[key] = 0;
      }

      final daily = learning.existingDailySession(on: day);
      if (daily != null) {
        final vocabRecord = daily.stages[PathwayStage.vocab];
        if (vocabRecord?.status == StageStatus.completed) {
          final rawIds = vocabRecord?.resultJson?['wordIds'];
          final ids = rawIds is List
              ? rawIds.whereType<String>()
              : daily.vocabEntryIds ?? const <String>[];
          for (final id in ids) {
            wordData.putIfAbsent(id, () => _WordAccumulator(id));
          }
          if (ids.isNotEmpty) activityDays.add(key);
        }
        if (daily.stages.values.any(
          (record) => record.status == StageStatus.completed,
        )) {
          activityDays.add(key);
        }
      }
    }

    final practiceSeconds = <String, int>{};
    for (var index = 0; index < 7; index++) {
      final day = weekStart.add(Duration(days: index));
      if (day.isAfter(today)) continue;
      final key = _dayKey(day);
      // Habit minutes and session timestamps cover the same speaking/writing
      // time. Taking the greater per day prevents counting that time twice.
      practiceSeconds[key] = [
        secondsByDay[key] ?? 0,
        (trackedHabitMinutes[key] ?? 0) * 60,
      ].reduce((a, b) => a > b ? a : b);
    }

    final words =
        wordData.values
            .map((word) {
              final grade = word.lastGrade;
              final remembered =
                  word.wasRecalled ||
                  grade == SRSGrade.good ||
                  grade == SRSGrade.easy;
              final needsReview =
                  word.needsAnotherLook ||
                  grade == SRSGrade.again ||
                  grade == SRSGrade.hard;
              final count = word.reviewEvents > 0
                  ? word.reviewEvents
                  : word.vocabularySessionAttempts.clamp(1, 999).toInt();
              return (
                word: word,
                remembered: remembered,
                needsReview: needsReview,
                count: count,
              );
            })
            .where((item) => entriesById.containsKey(item.word.entryId))
            .map(
              (item) => WeeklyWordProgress(
                entry: entriesById[item.word.entryId]!,
                practiceCount: item.count,
                wasRecalled: item.remembered,
                needsAnotherLook: item.needsReview,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            if (a.needsAnotherLook != b.needsAnotherLook) {
              return a.needsAnotherLook ? -1 : 1;
            }
            if (a.practiceCount != b.practiceCount) {
              return b.practiceCount.compareTo(a.practiceCount);
            }
            return a.entry.fr.compareTo(b.entry.fr);
          });

    final corrections = _correctionsInWeek(weekStart, weekEnd);
    final days = List<WeeklyReportDay>.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      final isFuture = weekOffset == 0 && date.isAfter(today);
      return WeeklyReportDay(
        date: date,
        isActive: !isFuture && activityDays.contains(_dayKey(date)),
        isFuture: isFuture,
        sessionCount: sessionsByDay[_dayKey(date)] ?? 0,
      );
    }, growable: false);

    return WeeklyReport(
      weekStart: weekStart,
      weekEndExclusive: weekEnd,
      asOf: localNow,
      days: days,
      sessions: sessions,
      skillSessionCounts: Map.unmodifiable(skillCounts),
      words: List.unmodifiable(words),
      corrections: List.unmodifiable(corrections),
      activeDays: activityDays.length,
      practiceMinutes:
          practiceSeconds.values.fold<int>(0, (a, b) => a + b) ~/ 60,
      speakingTurns: speakingTurns,
      speakingSessions: speakingSessions,
      latestLearnerLine: latestLearnerLine,
    );
  }

  List<WeeklyCorrection> _correctionsInWeek(DateTime start, DateTime end) {
    final byPair = <String, _CorrectionAccumulator>{};
    for (final submission in learning.submissions()) {
      final submittedAt = _date(submission.submittedAt)?.toLocal();
      if (submittedAt == null || !_inRange(submittedAt, start, end)) continue;
      try {
        final decoded = jsonDecode(submission.feedback);
        if (decoded is! Map) continue;
        final rawCorrections = decoded['corrections'];
        if (rawCorrections is! List) continue;
        for (final raw in rawCorrections) {
          if (raw is! Map) continue;
          final original = raw['original']?.toString().trim() ?? '';
          final corrected = raw['fixed']?.toString().trim() ?? '';
          if (original.isEmpty || corrected.isEmpty) continue;
          final key =
              '${original.toLowerCase()}\u0000${corrected.toLowerCase()}';
          final correction = byPair.putIfAbsent(
            key,
            () => _CorrectionAccumulator(
              original: original,
              corrected: corrected,
              explanation: raw['why']?.toString().trim() ?? '',
              submittedAt: submittedAt,
            ),
          );
          correction.timesSeen++;
          if (submittedAt.isAfter(correction.submittedAt)) {
            correction.submittedAt = submittedAt;
          }
        }
      } catch (_) {
        // Older writing screens saved plain text feedback. They remain visible
        // in Writing history, but are not treated as structured corrections.
      }
    }
    return byPair.values
        .map(
          (item) => WeeklyCorrection(
            original: item.original,
            corrected: item.corrected,
            explanation: item.explanation,
            submittedAt: item.submittedAt,
            timesSeen: item.timesSeen,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
  }

  static DateTime? _date(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static bool _inRange(DateTime date, DateTime start, DateTime end) =>
      !date.isBefore(start) && date.isBefore(end);

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String? _skillFor(String? raw) => switch (raw?.toLowerCase().trim()) {
    'vocab' || 'vocabulary' => 'Vocabulary',
    'grammar' => 'Grammar',
    'reading' || 'exam_reading' => 'Reading',
    'listening' || 'reading_listening' || 'exam_listening' => 'Listening',
    'writing' || 'exam_writing' => 'Writing',
    'speaking' ||
    'speaking_guided' ||
    'free_talk' ||
    'roleplay' ||
    'exam_speaking' ||
    'pronunciation_repair' ||
    'picture_description' ||
    'trial' => 'Speaking',
    _ => null,
  };

  static String _bounded(String value, int max) => value.length <= max
      ? value
      : '${value.substring(0, max - 1).trimRight()}…';
}

class _WordAccumulator {
  _WordAccumulator(this.entryId);

  final String entryId;
  int reviewEvents = 0;
  int vocabularySessionAttempts = 0;
  SRSGrade? lastGrade;
  DateTime? lastPractisedAt;
  bool wasRecalled = false;
  bool needsAnotherLook = false;

  void applyGrade(SRSGrade grade) {
    lastGrade = grade;
    wasRecalled = grade == SRSGrade.good || grade == SRSGrade.easy;
    needsAnotherLook = grade == SRSGrade.again || grade == SRSGrade.hard;
  }
}

class _CorrectionAccumulator {
  _CorrectionAccumulator({
    required this.original,
    required this.corrected,
    required this.explanation,
    required this.submittedAt,
  });

  final String original;
  final String corrected;
  final String explanation;
  DateTime submittedAt;
  int timesSeen = 0;
}
