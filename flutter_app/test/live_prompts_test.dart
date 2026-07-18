import 'package:flutter_test/flutter_test.dart';

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

    test('roleplay prompt locks the opposite-character role', () {
      final prompt = LivePrompts.forSession(LiveSessionType.speakingRoleplay);
      expect(prompt, contains('YOU PLAY THE OTHER CHARACTER'));
      expect(prompt, contains('ROLE-LOCK RULES'));
      expect(
        prompt,
        contains('ALWAYS RESPOND TO WHAT THE STUDENT JUST SAID'),
      );
      expect(prompt, contains('STAY IN CHARACTER'));
      expect(prompt, contains('COACH ONLY WHEN NEEDED'));
      // The conversational drivers that broke roleplay must NOT leak in.
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
