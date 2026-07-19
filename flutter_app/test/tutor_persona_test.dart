import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/prompts/live_prompts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('persona roster (P2.1)', () {
    test('exactly four personas: 2 per accent, 1F/1M per accent', () {
      expect(TutorPersona.all, hasLength(4));
      for (final accent in TutorAccent.values) {
        final pair = TutorPersona.byAccent(accent);
        expect(pair, hasLength(2), reason: '$accent');
        expect(pair.where((p) => p.isFemale), hasLength(1), reason: '$accent');
      }
    });

    test('ids and voices are unique; every field non-empty', () {
      expect(TutorPersona.all.map((p) => p.id).toSet(), hasLength(4));
      expect(TutorPersona.all.map((p) => p.voiceName).toSet(), hasLength(4));
      for (final p in TutorPersona.all) {
        expect(p.displayName, isNotEmpty);
        expect(p.tagline, isNotEmpty);
        expect(p.promptBlock, contains(p.displayName));
        expect(p.initial, p.displayName.substring(0, 1));
      }
    });

    test('byId falls back to Marie for unknown/legacy/null ids', () {
      expect(TutorPersona.byId('marie'), TutorPersona.marie);
      expect(TutorPersona.byId('mathieu'), TutorPersona.mathieu);
      expect(TutorPersona.byId('deleted_legacy_id'), TutorPersona.marie);
      expect(TutorPersona.byId(null), TutorPersona.marie);
    });

    test('Québec personas gloss their register; France stay standard', () {
      for (final p in TutorPersona.byAccent(TutorAccent.quebec)) {
        expect(p.promptBlock, contains('Québec French'));
        expect(p.promptBlock, contains('gloss it in English'));
      }
      for (final p in TutorPersona.byAccent(TutorAccent.france)) {
        expect(p.promptBlock, contains('metropolitan French'));
      }
    });
  });

  group('prompt composition (P2.1/P2.3)', () {
    test('every persona is composable into every session type', () {
      for (final persona in TutorPersona.all) {
        for (final type in LiveSessionType.values) {
          final prompt = LivePrompts.forSession(type, persona: persona);
          expect(prompt, contains('You are ${persona.displayName}'));
          expect(prompt, contains(LivePrompts.languageGuardrail));
          expect(prompt, contains(LivePrompts.contentSafety));
        }
      }
    });

    test('default persona remains Marie', () {
      expect(
        LivePrompts.forSession(LiveSessionType.freeTalk),
        contains('You are Marie'),
      );
    });

    test('language mix and pace lines are composed in', () {
      final gentle = LivePrompts.forSession(
        LiveSessionType.freeTalk,
        languageMix: 'gentle',
        voiceSpeed: 'slower',
      );
      expect(gentle, contains('LANGUAGE MIX: GENTLE'));
      expect(gentle, contains('speak noticeably slowly'));
      final immersive = LivePrompts.forSession(
        LiveSessionType.freeTalk,
        languageMix: 'immersive',
        voiceSpeed: 'faster',
      );
      expect(immersive, contains('LANGUAGE MIX: IMMERSION'));
      expect(immersive, contains('brisk'));
      // Mix is a preference, never an override of stage rules.
      expect(immersive, contains('those win'));
    });
  });

  group('persistence', () {
    test('ActiveTutor round-trips and defaults to Marie', () async {
      await ActiveTutor.load();
      expect(ActiveTutor.current, TutorPersona.marie);
      await ActiveTutor.set(TutorPersona.camille);
      expect(ActiveTutor.current, TutorPersona.camille);
      // Fresh load from the same prefs restores the choice.
      ActiveTutor.notifier.value = TutorPersona.marie;
      await ActiveTutor.load();
      expect(ActiveTutor.current, TutorPersona.camille);
    });

    test('TutorTuning round-trips and rejects garbage', () async {
      expect(await TutorTuning.languageMix(), 'balanced');
      expect(await TutorTuning.voiceSpeed(), 'natural');
      await TutorTuning.saveLanguageMix('immersive');
      await TutorTuning.saveVoiceSpeed('slower');
      expect(await TutorTuning.languageMix(), 'immersive');
      expect(await TutorTuning.voiceSpeed(), 'slower');
      // A corrupted stored value falls back to the defaults.
      SharedPreferences.setMockInitialValues({
        TutorTuning.mixKey: 'garbage',
        TutorTuning.speedKey: 'x',
      });
      expect(await TutorTuning.languageMix(), 'balanced');
      expect(await TutorTuning.voiceSpeed(), 'natural');
    });
  });
}
