import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/profile.dart';
import 'package:french_tutor/models/tutor_persona.dart';

void main() {
  group('LearnerLevel (onboarding v2)', () {
    test('CEFR values map to conversational correctly', () {
      expect(LearnerLevel.isConversational('a1'), isFalse);
      expect(LearnerLevel.isConversational('a2'), isFalse);
      expect(LearnerLevel.isConversational('b1'), isTrue);
      expect(LearnerLevel.isConversational('b2'), isTrue);
    });

    test('legacy values keep working — no migration needed', () {
      expect(LearnerLevel.isConversational('zero'), isFalse);
      expect(LearnerLevel.isConversational('basics'), isFalse);
      expect(LearnerLevel.isConversational('conversational'), isTrue);
      expect(LearnerLevel.isConversational('unsure'), isFalse);
      // Garbage never crashes, treated as beginner (the safe default).
      expect(LearnerLevel.isConversational(''), isFalse);
      expect(LearnerLevel.isConversational('c2'), isFalse);
    });

    test('language mix derives from level', () {
      expect(LearnerLevel.defaultLanguageMix('a1'), 'gentle');
      expect(LearnerLevel.defaultLanguageMix('a2'), 'gentle');
      expect(LearnerLevel.defaultLanguageMix('b1'), 'balanced');
      expect(LearnerLevel.defaultLanguageMix('b2'), 'immersive');
      expect(LearnerLevel.defaultLanguageMix('zero'), 'gentle');
      expect(LearnerLevel.defaultLanguageMix('conversational'), 'balanced');
    });

    test('derived mix values are always valid TutorTuning values', () {
      for (final level in [...LearnerLevel.cefrValues, 'zero', 'unsure', '']) {
        expect(
          TutorTuning.mixValues,
          contains(LearnerLevel.defaultLanguageMix(level)),
          reason: level,
        );
      }
    });

    test('display labels', () {
      expect(LearnerLevel.displayLabel('a1'), 'A1');
      expect(LearnerLevel.displayLabel('b2'), 'B2');
      expect(LearnerLevel.displayLabel('conversational'), 'Conversational');
      expect(LearnerLevel.displayLabel('whatever'), 'Exploring');
    });
  });

  group('voice preview samples (P2.2)', () {
    test('every persona has a substantial sample line', () {
      for (final p in TutorPersona.all) {
        expect(p.sampleLine.length, greaterThan(80), reason: p.id);
        expect(p.sampleLine, contains(p.displayName), reason: p.id);
      }
    });
  });
}
