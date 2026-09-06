import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/models/speaking_course.dart';
import 'package:french_tutor/screens/speak/speak_course_activity_screen.dart';
import 'package:french_tutor/screens/speak/speaking_lesson_flow_screen.dart';

void main() {
  test('every Course speaking-compatible row opens the guided phrase mode', () {
    expect(
      courseSpeakingModeFor(SpeakSkill.speaking),
      SpeakingCourseMode.guided,
    );
    expect(
      courseSpeakingModeFor(SpeakSkill.roleplay),
      SpeakingCourseMode.guided,
    );
    expect(
      courseSpeakingModeFor(SpeakSkill.freeTalk),
      SpeakingCourseMode.guided,
    );
  });

  test('guided Course speaking is voice recording at every CEFR level', () {
    const lines = [SpeakingCourseLine(french: 'Bonjour.', english: 'Hello.')];

    for (final level in ['A1', 'A2', 'B1', 'B2']) {
      final steps = speakingStepsForCourseLines(lines, level: level);
      expect(steps.single.stage, SpeakingGuidedStage.speak, reason: level);
    }
  });
}
