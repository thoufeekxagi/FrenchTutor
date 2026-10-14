import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/onboarding/v3_onboarding_flow.dart';

/// The last onboarding screen speaks to the learner by name, with their exam
/// date and the daily commitment they chose. Every combination reads well and
/// never promises a result.
void main() {
  final exam = DateTime(2027, 3, 14);

  test('name, exam date, time and days', () {
    final c = OnboardingPledgeCopy.build(
      name: 'Priya',
      exam: exam,
      timeLabel: '7:00 PM',
      dayIds: const ['mon', 'tue', 'wed', 'thu', 'fri'],
    );
    expect(c.title, 'Dear Priya,');
    expect(
      c.body,
      'ParleSprint is proud to help you get ready for your TCF Canada exam on March 14, 2027.',
    );
    expect(c.commitment, 'Your daily commitment: 7:00 PM, Monday to Friday.');
  });

  test('no name: a plain welcome, never "Dear ,"', () {
    for (final name in ['', '   ']) {
      expect(OnboardingPledgeCopy.build(name: name).title, 'Welcome,');
    }
  });

  test('the name is trimmed', () {
    expect(OnboardingPledgeCopy.build(name: '  Awa ').title, 'Dear Awa,');
  });

  test('no exam date: no invented date', () {
    final c = OnboardingPledgeCopy.build(name: 'Sam');
    expect(
      c.body,
      'ParleSprint is proud to help you get ready for the TCF Canada exam.',
    );
    expect(c.body, isNot(contains('on ')));
  });

  test('no reminder: an honest commitment line, no fake time', () {
    final c = OnboardingPledgeCopy.build(name: 'Sam', exam: exam);
    expect(
      c.commitment,
      'Your commitment: one lesson at a time, at your own pace.',
    );
  });

  test('a time without days (or days without a time) is not a commitment', () {
    expect(
      OnboardingPledgeCopy.build(name: 'Sam', timeLabel: '7:00 PM').commitment,
      startsWith('Your commitment:'),
    );
    expect(
      OnboardingPledgeCopy.build(name: 'Sam', dayIds: const ['mon']).commitment,
      startsWith('Your commitment:'),
    );
  });

  group('days label', () {
    test('every day', () {
      expect(
        OnboardingPledgeCopy.daysLabel(const [
          'sun',
          'mon',
          'tue',
          'wed',
          'thu',
          'fri',
          'sat',
        ]),
        'every day',
      );
    });
    test('Monday to Friday, whatever the order they were tapped in', () {
      expect(
        OnboardingPledgeCopy.daysLabel(const [
          'fri',
          'mon',
          'thu',
          'wed',
          'tue',
        ]),
        'Monday to Friday',
      );
    });
    test('five days that include a weekend are listed, in week order', () {
      expect(
        OnboardingPledgeCopy.daysLabel(const [
          'sat',
          'mon',
          'tue',
          'wed',
          'thu',
        ]),
        'Mon, Tue, Wed, Thu, Sat',
      );
    });
    test('a few days are listed in week order', () {
      expect(
        OnboardingPledgeCopy.daysLabel(const ['fri', 'mon', 'wed']),
        'Mon, Wed, Fri',
      );
    });
  });

  test('dates read in plain English for every month', () {
    final names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    for (var m = 1; m <= 12; m++) {
      expect(
        OnboardingPledgeCopy.examDate(DateTime(2027, m, 5)),
        '${names[m - 1]} 5, 2027',
      );
    }
  });

  test('the copy contains no promise of a score and no em dash', () {
    final c = OnboardingPledgeCopy.build(
      name: 'Priya',
      exam: exam,
      timeLabel: '7:00 PM',
      dayIds: const ['mon'],
    );
    final all = '${c.title} ${c.body} ${c.commitment}'.toLowerCase();
    expect(all, isNot(contains('guarantee')));
    expect(all, isNot(contains('you will pass')));
    expect(all.contains('\u2014'), isFalse);
  });
}
