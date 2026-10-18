import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Approved home layout, daily challenge, practice and progress routes.
/// Run with E2E_DEFINES='--dart-define=E2E_SHELL=true'.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List<String>> labels(WidgetTester tester) async =>
      (probe.describe(tester)['tappable']! as List)
          .map((entry) => (entry as Map)['label'] as String)
          .toList();

  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  testWidgets('approved home, daily challenge, practice and progress routes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    final originalExamDate = prefs.getString('tcf_exam_date');
    final originalProUnlock = prefs.getBool('dev_force_pro_unlock');
    final originalDarkChoice = prefs.getBool('app_dark_mode_v3_choice');
    final originalDarkMode = prefs.getBool('app_dark_mode');
    final now = DateTime.now().toLocal();
    final challengeKey =
        'e2e_daily_${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_a1-clinic-message-sample';
    final originalChallengeStep = prefs.getInt('$challengeKey.step');
    final originalChallengeComplete = prefs.getBool('$challengeKey.completed');
    addTearDown(() async {
      if (originalExamDate == null) {
        await prefs.remove('tcf_exam_date');
      } else {
        await prefs.setString('tcf_exam_date', originalExamDate);
      }
      if (originalProUnlock == null) {
        await prefs.remove('dev_force_pro_unlock');
      } else {
        await prefs.setBool('dev_force_pro_unlock', originalProUnlock);
      }
      if (originalDarkChoice == null) {
        await prefs.remove('app_dark_mode_v3_choice');
      } else {
        await prefs.setBool('app_dark_mode_v3_choice', originalDarkChoice);
      }
      if (originalDarkMode == null) {
        await prefs.remove('app_dark_mode');
      } else {
        await prefs.setBool('app_dark_mode', originalDarkMode);
      }
      if (originalChallengeStep == null) {
        await prefs.remove('$challengeKey.step');
      } else {
        await prefs.setInt('$challengeKey.step', originalChallengeStep);
      }
      if (originalChallengeComplete == null) {
        await prefs.remove('$challengeKey.completed');
      } else {
        await prefs.setBool(
          '$challengeKey.completed',
          originalChallengeComplete,
        );
      }
    });
    await prefs.remove('$challengeKey.step');
    await prefs.remove('$challengeKey.completed');
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    final examDate = DateTime.now().add(const Duration(days: 69));
    await prefs.setString('tcf_exam_date', examDate.toIso8601String());

    app.main();
    await probe.waitForLabel(
      tester,
      'Start challenge.',
      startsWith: true,
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));
    await probe.capture(tester, '01_approved_home');

    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.textScaleFactorTestValue = 2;
    await probe.settle(tester, timeout: const Duration(seconds: 10));
    await probe.capture(tester, '02_large_text_home');
    expect(tester.takeException(), isNull, reason: 'large text home layout');
    dispatcher.clearTextScaleFactorTestValue();
    await probe.settle(tester, timeout: const Duration(seconds: 10));

    final homeTexts = await texts(tester);
    expect(homeTexts, contains('Bonjour!'));
    expect(homeTexts, contains('CONTINUE YOUR COURSE'));
    expect(homeTexts, contains('Your practice'));
    expect(homeTexts, contains('Your TCF path'));
    expect(homeTexts, contains('Talk with Marie'));
    expect(homeTexts, contains('Daily challenge'));
    expect(homeTexts, contains('Stories'));
    expect(homeTexts, contains('A clinic message'));
    expect(homeTexts, isNot(contains('ParleSprint')));
    expect(homeTexts, isNot(contains('Today')));
    expect(homeTexts, contains('Exam in 69 days'));
    final homeLabels = await labels(tester);
    for (final label in ['Change level, A1', 'Exam in 69 days']) {
      expect(
        homeLabels,
        contains(label),
        reason: 'missing $label in $homeLabels',
      );
    }
    expect(
      homeLabels.any((label) => label.startsWith('Start challenge.')),
      isTrue,
    );
    expect(
      homeLabels.any((label) => label.startsWith('Review flashcards.')),
      isTrue,
    );
    expect(
      homeLabels.any((label) => label.startsWith('Continue lesson,')),
      isTrue,
    );
    expect(homeLabels, contains('View course path'));
    expect(homeLabels, contains('Talk with Marie. Conversation practice.'));
    expect(homeLabels, contains('Open Stories. Read or listen.'));
    for (final tab in ['Learn', 'Marie', 'Tests', 'Me']) {
      expect(homeLabels, contains(tab));
    }

    // Open and retain the selected level, then verify the course hero enters
    // the authored lesson player without advancing its saved position.
    await probe.tapLabel(tester, 'Change level, A1');
    await probe.waitForLabel(tester, 'A1 level');
    await probe.tapLabel(tester, 'A1 level');
    await probe.tapLabel(tester, 'Continue lesson,', startsWith: true);
    await probe.waitForLabel(tester, 'Close lesson');
    await probe.tapLabel(tester, 'Close lesson');
    await probe.waitForLabel(tester, 'Start challenge.', startsWith: true);

    // Walk through each authored step without relying on network audio.
    await probe.tapLabel(tester, 'Start challenge.', startsWith: true);
    await probe.waitFor(
      tester,
      find.text('What time is the appointment?'),
      timeout: const Duration(seconds: 15),
    );
    await probe.capture(tester, '02_daily_listening');
    expect(await texts(tester), contains('LISTEN ONCE'));
    await tester.tap(find.byKey(const ValueKey('lesson.option.3')));
    await tester.pump(const Duration(milliseconds: 150));
    await probe.tapLabel(tester, 'Check');
    await probe.waitFor(tester, find.text('Correct'));
    await tester.pump(const Duration(milliseconds: 500));
    await probe.tapLabel(tester, 'Continue');
    await probe.waitFor(
      tester,
      find.text('Read the clinic notice. When is this clinic open?'),
    );
    await tester.tap(find.byKey(const ValueKey('lesson.option.2')));
    await tester.pump(const Duration(milliseconds: 150));
    await probe.tapLabel(tester, 'Check');
    await probe.waitFor(tester, find.text('Correct'));
    await tester.pump(const Duration(milliseconds: 500));
    await probe.tapLabel(tester, 'Continue');
    await probe.waitFor(tester, find.text('Je voudrais un rendez-vous.'));
    await probe.tapLabel(tester, 'Continue');
    await probe.waitFor(tester, find.text('Challenge complete'));
    await probe.capture(tester, '03_daily_complete');
    await probe.tapLabel(tester, 'Done');
    await probe.waitFor(tester, find.text('Completed today'));

    // The home practice tiles open Marie, review, and the fuller practice
    // destination without a Course/Practice segment on the approved screen.
    await probe.tapLabel(tester, 'Talk with Marie. Conversation practice.');
    await probe.waitForLabel(tester, 'Back');
    await tester.pageBack();
    await probe.waitForLabel(tester, 'Review flashcards.', startsWith: true);
    final reviewLabel = (await labels(
      tester,
    )).firstWhere((label) => label.startsWith('Review flashcards.'));
    await probe.tapLabel(tester, reviewLabel);
    await probe.tapLabel(tester, 'Open Stories. Read or listen.');
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    final practiceLabels = await labels(tester);
    expect(practiceLabels, contains('Read stories'));
    expect(practiceLabels, contains('Listen stories'));
    expect(practiceLabels, contains('Explore practice library'));
    await probe.capture(tester, '04_practice');

    // The streak calendar opens from the home and refreshes the challenge
    // state after the local walkthrough finishes.
    await probe.tapLabel(tester, 'Back home');
    await probe.tapLabel(tester, 'View course path');
    await probe.waitFor(tester, find.text('Your course path'));
    await probe.capture(tester, '05_course_path');
    await probe.tapLabel(tester, 'Back home');
    await prefs.remove('$challengeKey.step');
    await prefs.remove('$challengeKey.completed');
    final courseLabels = await labels(tester);
    final streakLabel = courseLabels.firstWhere(
      (label) => label.startsWith('Open streak calendar,'),
    );
    await probe.tapLabel(tester, streakLabel);
    await probe.waitFor(tester, find.text('Your streak'));
    await probe.capture(tester, '05_streak_calendar');
    expect(await texts(tester), contains('Recent activity'));
    await probe.tapLabel(tester, 'Back');
    await probe.waitForLabel(tester, 'Start challenge.', startsWith: true);
    semantics.dispose();
  });
}
