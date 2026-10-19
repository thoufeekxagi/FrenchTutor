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

    test('lesson coach has a short, learner-controlled reply contract', () {
      final prompt = LivePrompts.compactLessonCoach(
        persona: TutorPersona.marie,
      );
      expect(prompt, contains('ANSWER FIRST, THEN STOP'));
      expect(prompt, contains('about 8 to 25 words'));
      expect(prompt, contains('until they change it'));
      expect(prompt, contains('If they say stop, stop'));
      expect(prompt, contains('TEACH WITH ONE MOVE'));
      expect(prompt, contains('REPEAT OR SLOWER'));
      expect(prompt, contains('LANGUAGE (hard rule)'));
      expect(prompt, contains('stop at'));
      expect(prompt, contains('INTERRUPTIONS AND NOISE'));
    });

    test(
      'Live tutor follows the learner and treats course context as optional',
      () {
        final prompt = LivePrompts.forSession(LiveSessionType.liveTutor);
        expect(prompt, contains('INDEPENDENT LIVE TUTOR'));
        expect(prompt, contains('COURSE BRIDGE RULE'));
        expect(prompt, contains('optional inspiration only'));
        expect(prompt, contains('create useful vocabulary'));
        expect(prompt, contains('learner wants to talk about'));
        expect(prompt, contains('not a scripted lesson'));
      },
    );

    test('compact Live Tutor language policy is strict by CEFR level', () {
      final a1 = LivePrompts.compactLiveTutor(
        persona: TutorPersona.marie,
        level: 'A1',
      );
      final a2 = LivePrompts.compactLiveTutor(
        persona: TutorPersona.marie,
        level: 'A2',
      );
      final b1 = LivePrompts.compactLiveTutor(
        persona: TutorPersona.marie,
        level: 'B1',
      );
      final b2 = LivePrompts.compactLiveTutor(
        persona: TutorPersona.marie,
        level: 'B2',
      );

      expect(a1, contains('roughly half'));
      expect(a1, contains('English orientation'));
      expect(a2, contains('balanced English and French'));
      for (final prompt in [b1, b2]) {
        expect(prompt, contains('FRENCH ONLY'));
        expect(prompt, contains('Never speak English'));
        expect(prompt, contains('explanations, corrections, examples'));
        expect(prompt, contains('respond in French and continue'));
      }
    });

    test(
      'compact Live Tutor keeps normal replies short but can teach in depth',
      () {
        final prompt = LivePrompts.compactLiveTutor(
          persona: TutorPersona.marie,
          level: 'A1',
        );

        expect(prompt, contains('CONDUCT (hard rules)'));
        expect(prompt, contains('one or two short sentences'));
        expect(prompt, contains('asks you to explain'));
        expect(prompt, contains('Never say "anything else?"'));
        expect(
          prompt,
          contains('never end two turns in a row with a question'),
        );
        expect(prompt, contains('Speak only English and French'));
      },
    );

    test(
      'every Talk with Marie mode is a teaching routine with the shared rules',
      () {
        for (final (mode, marker) in const [
          ('talk', 'TALK IT THROUGH'),
          ('fix', 'FIX MY FRENCH'),
          ('tcf', 'TCF-STYLE SPEAKING DRILL'),
          ('words', 'WORDS AND PRONUNCIATION'),
        ]) {
          final prompt = LivePrompts.talkTutor(
            persona: TutorPersona.marie,
            level: 'A2',
            mode: mode,
            focus: 'canada',
          );
          expect(prompt, contains(marker), reason: mode);
          expect(prompt, contains('life in Canada and immigration'));
          expect(prompt, contains('CONDUCT (hard rules)'));
          expect(prompt, contains('Speak only English and French'));
          expect(prompt, contains('LEVEL LANGUAGE POLICY'));
          expect(prompt, contains('one prompt per turn'));
          expect(prompt, isNot(contains('never end two turns')));
        }
      },
    );

    test('the TCF drill never scores or claims to be the official exam', () {
      final brief = LivePrompts.talkModeBrief('tcf');
      expect(brief, contains('never claim this is the official exam'));
      expect(brief.replaceAll('\n', ' '), contains('Never give a score'));
    });

    test('each opening starts the mode with a concrete first action', () {
      for (final (mode, action) in const [
        ('fix', 'one sentence in French'),
        ('tcf', 'Task 1'),
        ('words', 'say it slowly'),
        ('talk', 'one easy question'),
      ]) {
        expect(
          LivePrompts.talkOpening(mode: mode, focus: 'Work and study'),
          contains(action),
          reason: mode,
        );
      }
      final opening = LivePrompts.talkOpening(
        mode: 'fix',
        focus: 'Work and study',
      );
      expect(opening, contains('At most two short sentences'));
    });

    test('every mode has a short reminder that names the mode', () {
      for (final (mode, name) in const [
        ('talk', 'TALK IT THROUGH'),
        ('fix', 'FIX MY FRENCH'),
        ('tcf', 'TCF-STYLE DRILL'),
        ('words', 'WORDS AND PRONUNCIATION'),
      ]) {
        final note = LivePrompts.talkModeReminder(mode);
        expect(note, contains(name), reason: mode);
        expect(note.length, lessThan(300), reason: mode);
      }
    });

    test('the onboarding calibration keeps its probing questions', () {
      final prompt = LivePrompts.compactOnboardingCalibration(
        persona: TutorPersona.marie,
      );
      expect(prompt, contains('one short probing question at a time'));
      expect(prompt, contains('CONDUCT (hard rules)'));
      expect(prompt, isNot(contains('never end two turns')));
    });

    test(
      'Live Tutor kickoff asks for a fresh topic-based intro, not a script',
      () {
        final kickoff = LivePrompts.liveTutorKickoff(
          topic: 'Daily life',
          style: 'Sharp',
          courseFocus: 'Talking about friends',
        );

        expect(kickoff, contains('vary the angle and wording each session'));
        expect(kickoff, contains('concrete, easy conversational hook'));
        expect(kickoff, contains('Talking about friends'));
        expect(kickoff, isNot(contains('Bonjour, je suis')));
        expect(kickoff, isNot(contains('what do you want to learn today')));
      },
    );

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

    test('compact guided speaking feedback stays brief and current', () {
      final prompt = LivePrompts.compactGuidedSpeaking(
        persona: TutorPersona.marie,
      );
      expect(prompt, contains('plain confirmation'));
      expect(prompt, contains('Good pronunciation'));
      expect(prompt, contains('one improvement'));
      expect(prompt, contains('If the audio is'));
      expect(prompt, contains('Never continue or finish a sentence'));
      expect(prompt, contains('priority over your previous reply'));
      expect(
        prompt,
        contains('clearly asks a question about the current word'),
      );
      expect(prompt, contains('answer it directly in one brief sentence'));
      expect(prompt, contains('no extra praise or follow-up question'));
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
