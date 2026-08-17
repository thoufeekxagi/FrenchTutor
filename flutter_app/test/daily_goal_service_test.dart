import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/services/daily_goal_service.dart';

void main() {
  test('a new learner starts with a simple vocabulary first step', () {
    final profile = Profile(id: 'new', goal: 'everyday');

    expect(
      DailyGoalService.missionOrderFor(profile, hasHistory: false).first,
      'Vocabulary',
    );
  });

  test(
    'an everyday learner gets a conversation-led roadmap after starting',
    () {
      final profile = Profile(id: 'returning', goal: 'everyday');
      final order = DailyGoalService.missionOrderFor(profile);

      expect(order, [
        'Speaking',
        'Roleplay',
        'Listening',
        'Vocabulary',
        'Grammar',
        'Writing',
      ]);
      expect(
        DailyGoalService.nextCategory({'Speaking'}, order: order),
        'Roleplay',
      );
    },
  );
}
