import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/services/adaptive_curriculum_service.dart';

void main() {
  test('goal tracks expose distinct paid-use contexts', () {
    final work = AdaptiveCurriculumService.forProfile(
      Profile(id: 'work', goal: 'work', level: 'a1'),
    );
    final exam = AdaptiveCurriculumService.forProfile(
      Profile(id: 'exam', goal: 'tef_canada', level: 'b1'),
    );

    expect(work.label, 'Professional French');
    expect(work.contexts, contains('meetings, clarification, and teamwork'));
    expect(exam.label, 'TEF / TCF Canada');
    expect(exam.examName, 'TEF/TCF Canada');
    expect(
      exam.contexts,
      contains('timed speaking, listening, reading, and writing tasks'),
    );
  });

  test('relevant interests are filtered by the active goal', () {
    expect(
      AdaptiveCurriculumService.relevantInterest(
        Profile(id: 'learner', goal: 'work', interests: const ['Meetings']),
      ),
      'Meetings',
    );
    expect(
      AdaptiveCurriculumService.relevantInterest(
        Profile(
          id: 'learner',
          goal: 'relocation',
          interests: const ['Meetings'],
        ),
      ),
      isNull,
    );
  });

  test('focus skills default to all six and accept a single emphasis', () {
    expect(
      AdaptiveCurriculumService.focusSkills(Profile(id: 'new')),
      AdaptiveCurriculumService.coreFocusSkills,
    );
    expect(
      AdaptiveCurriculumService.focusSkills(
        Profile(id: 'listener', interests: const ['Listening']),
      ),
      [SpeakSkill.listening],
    );
  });
}
