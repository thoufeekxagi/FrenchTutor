import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/prompts/live_prompts.dart';
import 'package:french_tutor/services/lesson_agent_service.dart';

void main() {
  group('LivePrompts', () {
    test('every session type carries the absolute language guardrail', () {
      for (final type in LiveSessionType.values) {
        final prompt = LivePrompts.forSession(type);
        expect(
          prompt.contains(LivePrompts.languageGuardrail),
          isTrue,
          reason: 'guardrail missing from $type',
        );
      }
    });

    test('guardrail states the French/English-only rule explicitly', () {
      expect(
        LivePrompts.languageGuardrail,
        contains('French and English only'),
      );
      expect(LivePrompts.languageGuardrail, contains('NO EXCEPTIONS'));
      // Strict pilot rule: no engaging with other languages at all.
      expect(LivePrompts.languageGuardrail, contains('do NOT translate'));
      expect(LivePrompts.languageGuardrail, contains('do NOT engage'));
    });

    test('every session type carries the content-safety policy', () {
      for (final type in LiveSessionType.values) {
        final prompt = LivePrompts.forSession(type);
        expect(
          prompt.contains(LivePrompts.contentSafety),
          isTrue,
          reason: 'content policy missing from $type',
        );
      }
      expect(LivePrompts.contentSafety, contains('CONTENT POLICY'));
      expect(LivePrompts.contentSafety, contains('never use profanity'));
      expect(LivePrompts.contentSafety, contains('never repeat their words'));
    });

    test('every session type carries the shared persona base', () {
      for (final type in LiveSessionType.values) {
        final prompt = LivePrompts.forSession(type);
        expect(prompt, contains('You are Marie'));
        expect(prompt, contains('one to three sentences max'));
      }
    });

    test('free talk keeps its conversational drivers', () {
      final prompt = LivePrompts.forSession(LiveSessionType.freeTalk);
      expect(prompt, contains('OPEN CONVERSATION PRACTICE'));
      expect(prompt, contains('one simple follow-up question'));
      expect(prompt, contains('START THE CALL WITH A WARM GREETING'));
    });

    test('onboarding calibration uses the selected goal and level', () {
      final role = LivePrompts.forSession(
        LiveSessionType.onboardingCalibration,
      );
      final prompt = LivePrompts.trialLessonContextFor(
        goal: 'work',
        level: 'a2',
        focus: const ['Speaking', 'Grammar'],
        tutorName: 'Marie',
      );
      expect(role, contains('OPTIONAL ONBOARDING CALIBRATION'));
      expect(
        prompt,
        contains('Learner goal: Work and professional life (work)'),
      );
      expect(prompt, contains('self-reported level: A2'));
      expect(prompt, contains('Speaking, Grammar'));
      expect(prompt, contains('mostly English scaffolding'));
      expect(prompt, isNot(contains('fixed greetings sequence')));
      expect(prompt, contains('studied any French before'));
      expect(prompt, isNot(contains('ordering a coffee')));
      expect(
        LivePrompts.trialKickoffFor(goal: 'work', level: 'b1'),
        allOf(contains('French'), isNot(contains('English sentence'))),
      );
      expect(LivePrompts.trialWrapUpNote, isNot(contains('fixed')));
    });

    test('roleplay prompt locks the opposite-character role', () {
      final prompt = LivePrompts.forSession(LiveSessionType.speakingRoleplay);
      expect(prompt, contains('YOU PLAY THE OTHER CHARACTER'));
      expect(prompt, contains('ROLE-LOCK RULES'));
      expect(prompt, contains('ALWAYS RESPOND TO WHAT THE STUDENT JUST SAID'));
      expect(prompt, contains('STAY IN CHARACTER'));
      expect(prompt, contains('COACH ONLY WHEN NEEDED'));
      // The conversational drivers that broke roleplay must NOT leak in.
      expect(prompt, isNot(contains('one simple follow-up question')));
    });

    test('Smart Review speaking prompt cannot fall into a stock roleplay', () {
      final prompt = LivePrompts.forSession(LiveSessionType.speakingReview);
      expect(prompt, contains('DETERMINISTIC PERSONAL REVIEW COACH'));
      expect(prompt, contains('Do not turn this call into a roleplay'));
      expect(prompt, contains('Never invent or mention a café'));
      expect(prompt, contains('Never use a stock roleplay opening'));
      expect(prompt, isNot(contains('YOU PLAY THE OTHER CHARACTER')));
    });

    test(
      'guided conversation prompt enforces repeat, repair, and transfer',
      () {
        final prompt = LivePrompts.forSession(LiveSessionType.speakingGuided);
        expect(prompt, contains('GUIDED CONVERSATION COACH'));
        expect(prompt, contains('Ask the learner to repeat the phrase'));
        expect(prompt, contains('ONE high-value issue only'));
        expect(prompt, contains('Transfer the phrase'));
        expect(prompt, isNot(contains('one simple follow-up question')));
      },
    );

    test('speaking exam disables coaching and separates task behavior', () {
      final prompt = LivePrompts.forSession(LiveSessionType.speakingExam);
      expect(prompt, contains('TIMED SPEAKING EXAMINER'));
      expect(prompt, contains('Never coach'));
      expect(prompt, contains('For MONOLOGUE'));
      expect(prompt, contains('For INTERACTION'));
      expect(prompt, isNot(contains('one simple follow-up question')));
    });

    test('structured stages get the app-directed discipline block', () {
      for (final type in [
        LiveSessionType.vocabStage,
        LiveSessionType.listeningScene,
        LiveSessionType.grammarStage,
      ]) {
        final prompt = LivePrompts.forSession(type);
        expect(prompt, contains('APP-DIRECTED STAGE'), reason: '$type');
        expect(prompt, contains('Never suggest moving on'), reason: '$type');
        expect(
          prompt,
          isNot(contains('one simple follow-up question')),
          reason: 'conversational drivers must not leak into $type',
        );
      }
    });

    test('grammar stage never leaks a hidden answer before submission', () {
      final prompt = LivePrompts.forSession(LiveSessionType.grammarStage);
      expect(prompt, contains('missing French form and completed target'));
      expect(
        prompt,
        contains('Do not read the English instruction as a translation'),
      );
      expect(prompt, contains('without naming any option'));
    });

    test('compact vocabulary feedback is specific and restrained', () {
      final prompt = LivePrompts.compactVocabulary(persona: TutorPersona.marie);
      expect(prompt, contains('judge only that current target'));
      expect(prompt, contains('specific confirmation such as'));
      expect(prompt, contains('Vary the wording naturally'));
      expect(prompt, contains('pronunciation"'));
      expect(prompt, contains('one concrete'));
      expect(prompt, contains('could not hear'));
      expect(prompt, contains('generic motivational filler'));
      expect(prompt, contains('fantastic'));
      expect(prompt, contains('learner in control of the pace'));
      expect(prompt, isNot(contains('one short correction or encouragement')));
    });

    test(
      'compact writing course guide follows the grammar screen contract',
      () {
        final prompt = LivePrompts.compactGuidedWriting(
          persona: TutorPersona.marie,
        );
        expect(prompt, contains('APP OPENING'));
        expect(prompt, contains('APP SCREEN CHANGED'));
        expect(prompt, contains('APP FEEDBACK'));
        expect(prompt, contains('Never fill the blank'));
        expect(prompt, contains('never name, spell, translate, or assemble'));
        expect(prompt, contains('VISIBLE HINT'));
        expect(prompt, contains('explicitly asks for the answer'));
        expect(prompt, contains('APP COMMAND'));
        expect(prompt, contains('Never select, grade, advance'));
      },
    );
  });

  group('LessonAgentService guardrail', () {
    test('text-brain guardrail states the French/English-only rule', () {
      expect(
        LessonAgentService.languageGuardrail,
        contains('ONLY in French and English'),
      );
      expect(LessonAgentService.languageGuardrail, contains('ABSOLUTE'));
    });

    test('text-brain guardrail carries the content policy', () {
      expect(LessonAgentService.languageGuardrail, contains('CONTENT POLICY'));
      expect(
        LessonAgentService.languageGuardrail,
        contains('never use profanity'),
      );
    });
  });
}
