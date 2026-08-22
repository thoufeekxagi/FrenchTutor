import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/speaking_task_plan.dart';

void main() {
  group('SpeakingTaskPlan', () {
    const modes = [
      'guided_conversation',
      'roleplay',
      'free_talk',
      'tef_section_a',
      'tef_section_b',
      'picture_description',
      'pronunciation_repair',
    ];

    test('every public speaking mode produces a concrete plan', () {
      for (final mode in modes) {
        final plan = SpeakingTaskPlan.create(
          mode: mode,
          level: 'B1',
          topic: 'Travel',
          goal: 'Fluency',
        );

        expect(plan.mode, mode);
        expect(plan.title, isNotEmpty, reason: mode);
        expect(plan.stages, isNotEmpty, reason: mode);
        expect(plan.successCriteria, isNotEmpty, reason: mode);
        expect(plan.rubricFocus, isNotEmpty, reason: mode);
        expect(plan.liveContext, contains('SPEAKING TASK PLAN'), reason: mode);
        expect(plan.liveContext, contains('APP PACING RULES'), reason: mode);
      }
    });

    test('guided conversation exposes the repeat and repair loop', () {
      final plan = SpeakingTaskPlan.create(
        mode: 'guided_conversation',
        level: 'A1',
        topic: 'Café',
        goal: 'Pronunciation',
      );

      expect(plan.modeLabel, 'Guided conversation');
      expect(plan.liveContext, contains('repeat it aloud'));
      expect(plan.liveContext, contains('immediate feedback'));
      expect(plan.liveContext, contains('without reading it'));
    });

    test('the selected CEFR level is a hard lock in the live contract', () {
      final a1 = SpeakingTaskPlan.create(
        mode: 'guided_conversation',
        level: 'A1',
        topic: 'Travel',
        goal: 'Fluency',
      );
      final b2 = SpeakingTaskPlan.create(
        mode: 'guided_conversation',
        level: 'B2',
        topic: 'Travel',
        goal: 'Fluency',
      );

      expect(a1.liveContext, contains('Learner level: A1'));
      expect(a1.liveContext, contains('3–6 words'));
      expect(
        a1.liveContext,
        contains('Introduce no more than one new content word'),
      );
      expect(a1.liveContext, contains('Never introduce advanced idioms'));
      expect(b2.liveContext, contains('Learner level: B2'));
      expect(b2.liveContext, contains('10–18 words'));
      expect(b2.liveContext, contains('mostly French'));
      expect(b2.liveContext, isNot(contains('near-zero vocabulary')));
    });

    test('TEF sections retain their distinct assessment objective', () {
      final obtain = SpeakingTaskPlan.create(
        mode: 'tef_section_a',
        level: 'A2',
        topic: 'Airport',
        goal: 'Fluency',
      );
      final convince = SpeakingTaskPlan.create(
        mode: 'tef_section_b',
        level: 'B2',
        topic: 'Travel',
        goal: 'Fluency',
      );

      expect(obtain.examSection, 'A');
      expect(obtain.objective, contains('gather information'));
      expect(convince.examSection, 'B');
      expect(convince.objective, contains('respond to disagreement'));
    });

    test('legacy level aliases resolve to the four CEFR buckets', () {
      expect(SpeakingTaskPlan.normalizeLevel('basics'), 'A1');
      expect(SpeakingTaskPlan.normalizeLevel('conversational'), 'B1');
      expect(SpeakingTaskPlan.normalizeLevel('B2'), 'B2');
    });
  });
}
