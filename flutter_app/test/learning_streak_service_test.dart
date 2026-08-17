import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/session.dart';
import 'package:french_tutor/services/learning_streak_service.dart';

void main() {
  final now = DateTime(2026, 8, 16, 10);

  Session sessionOn(DateTime day, {bool finished = true}) => Session(
    id: day.toIso8601String(),
    startedAt: day.toIso8601String(),
    endedAt: finished
        ? day.add(const Duration(minutes: 10)).toIso8601String()
        : null,
    stage: 'speaking',
  );

  test('counts any completed learning day and keeps a current streak', () {
    final result = LearningStreakService.summarize([
      sessionOn(now),
      sessionOn(now.subtract(const Duration(days: 1))),
      sessionOn(now.subtract(const Duration(days: 2))),
    ], now: now);

    expect(result.currentDays, 3);
    expect(result.longestDays, 3);
  });

  test('does not count unfinished sessions or bridge a missing day', () {
    final result = LearningStreakService.summarize([
      sessionOn(now),
      sessionOn(now.subtract(const Duration(days: 1)), finished: false),
      sessionOn(now.subtract(const Duration(days: 3))),
      sessionOn(now.subtract(const Duration(days: 4))),
    ], now: now);

    expect(result.currentDays, 1);
    expect(result.longestDays, 2);
  });

  test(
    'allows yesterday to keep the streak alive while today is in progress',
    () {
      final result = LearningStreakService.summarize([
        sessionOn(now.subtract(const Duration(days: 1))),
        sessionOn(now.subtract(const Duration(days: 2))),
      ], now: now);

      expect(result.currentDays, 2);
    },
  );
}
