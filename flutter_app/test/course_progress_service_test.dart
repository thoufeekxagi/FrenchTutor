import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/services/course_progress_service.dart';

void main() {
  test(
    'course activity progress completes after the core learning loop',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final service = CourseProgressService(preferences: preferences);

      for (final skill in const [
        SpeakSkill.vocabulary,
        SpeakSkill.speaking,
        SpeakSkill.writing,
      ]) {
        await service.recordActivity(
          contentKey: 'a1_course_1',
          skill: skill,
          elapsed: const Duration(seconds: 2),
        );
      }

      expect(
        await service.shouldAutoComplete(
          contentKey: 'a1_course_1',
          estimatedMinutes: 7,
        ),
        isTrue,
      );
    },
  );

  test('a quick single activity does not complete a course session', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final service = CourseProgressService(preferences: preferences);

    await service.recordActivity(
      contentKey: 'a1_course_2',
      skill: SpeakSkill.vocabulary,
      elapsed: const Duration(seconds: 5),
    );

    expect(
      await service.shouldAutoComplete(
        contentKey: 'a1_course_2',
        estimatedMinutes: 7,
      ),
      isFalse,
    );
  });
}
