import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/liaison_curriculum_catalog.dart';

void main() {
  group('LiaisonCurriculumCatalog', () {
    test('contains the frozen 60-lesson level split', () {
      expect(LiaisonCurriculumCatalog.all, hasLength(60));
      expect(LiaisonCurriculumCatalog.forLevel('A1'), hasLength(30));
      expect(LiaisonCurriculumCatalog.forLevel('A2'), hasLength(20));
      expect(LiaisonCurriculumCatalog.forLevel('B1'), hasLength(10));
      expect(LiaisonCurriculumCatalog.forLevel('B2'), hasLength(10));
    });

    test('uses stable unique ids and complete lesson content', () {
      final ids = LiaisonCurriculumCatalog.all
          .map((lesson) => lesson.id)
          .toSet();
      expect(ids, hasLength(LiaisonCurriculumCatalog.all.length));
      for (final lesson in LiaisonCurriculumCatalog.all) {
        expect(lesson.title.trim(), isNotEmpty);
        expect(lesson.firstWord.trim(), isNotEmpty);
        expect(lesson.secondWord.trim(), isNotEmpty);
        expect(lesson.sentence.trim(), isNotEmpty);
        expect(lesson.sentenceEnglish.trim(), isNotEmpty);
        expect(lesson.passage.trim(), isNotEmpty);
        expect(lesson.passageEnglish.trim(), isNotEmpty);
        expect(
          LiaisonCurriculumCatalog.byProgressId(lesson.progressId)?.id,
          lesson.id,
        );
      }
    });

    test('keeps the A1 path on obligatory beginner links', () {
      expect(
        LiaisonCurriculumCatalog.forLevel(
          'A1',
        ).every((lesson) => lesson.ruleType == LiaisonRuleType.obligatory),
        isTrue,
      );
    });
  });
}
