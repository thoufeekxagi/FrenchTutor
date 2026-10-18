import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/access/v3_access.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/v3_cloud_state.dart';

V3Lesson _lesson(String id) => V3Lesson(
  id: id,
  title: id,
  subtitle: '',
  minutes: 5,
  steps: const [],
  unit: '',
  unitTitle: '',
);

void main() {
  group('lessons', () {
    test('stage 0 and the dev sample are always free', () {
      for (final id in ['s0-01', 's0-13', 'dev-sample']) {
        expect(
          V3Access.lessonLocked(lessonId: id, indexInLevel: 50, premium: false),
          isFalse,
          reason: id,
        );
      }
    });

    test('the first 7 lessons of each level are free, the 8th is locked', () {
      for (final level in ['a1', 'a2', 'b1', 'b2']) {
        for (var i = 0; i < 7; i++) {
          expect(
            V3Access.lessonLocked(
              lessonId: '$level-u01-words-1',
              indexInLevel: i,
              premium: false,
            ),
            isFalse,
            reason: '$level lesson ${i + 1}',
          );
        }
        expect(
          V3Access.lessonLocked(
            lessonId: '$level-u02-words-1',
            indexInLevel: 7,
            premium: false,
          ),
          isTrue,
          reason: '$level lesson 8',
        );
      }
    });

    test('a subscriber is never locked out', () {
      expect(
        V3Access.lessonLocked(
          lessonId: 'b2-u09-words-1',
          indexInLevel: 99,
          premium: true,
        ),
        isFalse,
      );
    });

    test('lesson position is counted inside its own level', () {
      final all = [
        for (var i = 0; i < 13; i++) _lesson('s0-${i + 1}'),
        for (var i = 0; i < 9; i++) _lesson('a1-u0${i + 1}-x'),
        for (var i = 0; i < 9; i++) _lesson('a2-u0${i + 1}-x'),
      ];
      expect(V3Access.indexInLevel(all[13], all), 0);
      expect(V3Access.indexInLevel(all[13 + 7], all), 7);
      expect(V3Access.indexInLevel(all[22], all), 0);
    });
  });

  group('daily challenges', () {
    final days = {for (var i = 1; i <= 7; i++) '2026-10-0$i'};
    test('7 days are free, an 8th new day is locked', () {
      expect(
        V3Access.dailyChallengeLocked(
          usedDays: days,
          today: '2026-10-08',
          premium: false,
        ),
        isTrue,
      );
    });
    test('a day already used stays open, and 6 days leaves room', () {
      expect(
        V3Access.dailyChallengeLocked(
          usedDays: days,
          today: '2026-10-07',
          premium: false,
        ),
        isFalse,
      );
      expect(
        V3Access.dailyChallengeLocked(
          usedDays: {...days}..remove('2026-10-07'),
          today: '2026-10-08',
          premium: false,
        ),
        isFalse,
      );
    });
    test('a subscriber is never locked out', () {
      expect(
        V3Access.dailyChallengeLocked(
          usedDays: days,
          today: '2026-10-09',
          premium: true,
        ),
        isFalse,
      );
    });
  });

  group('practice and exam', () {
    test('7 free uses, then locked', () {
      expect(V3Access.practiceLocked(uses: 6, premium: false), isFalse);
      expect(V3Access.practiceLocked(uses: 7, premium: false), isTrue);
      expect(V3Access.practiceLocked(uses: 7, premium: true), isFalse);
    });

    test('tests are free for 7 calendar days from the first day', () {
      final start = DateTime(2026, 10, 1, 23, 50);
      DateTime day(int d) => DateTime(2026, 10, d, 0, 5);
      expect(
        V3Access.examLocked(startedOn: start, now: day(7), premium: false),
        isFalse,
      );
      expect(V3Access.examDaysLeft(start, day(7)), 1);
      expect(
        V3Access.examLocked(startedOn: start, now: day(8), premium: false),
        isTrue,
      );
      expect(V3Access.examDaysLeft(start, day(9)), 0);
      expect(
        V3Access.examLocked(startedOn: start, now: day(20), premium: true),
        isFalse,
      );
    });
  });

  group('allowance survives a reinstall (account merge)', () {
    test('the earliest start day, the most uses and every used day win', () {
      expect(
        V3CloudState.merge(V3StateKind.earliest, '2026-10-12', '2026-10-05'),
        '2026-10-05',
      );
      expect(
        V3CloudState.merge(V3StateKind.earliest, null, '2026-10-05'),
        '2026-10-05',
      );
      expect(V3CloudState.merge(V3StateKind.max, 3, 5), 5);
      expect(V3CloudState.merge(V3StateKind.max, 6, 2), 6);
      expect(V3CloudState.merge(V3StateKind.max, null, 4), 4);
      expect(
        V3CloudState.merge(V3StateKind.set, ['2026-10-01'], ['2026-10-02']),
        ['2026-10-01', '2026-10-02'],
      );
    });
  });
}
