import '../lib/data/liaison_curriculum_catalog.dart';

Never fail(String message) => throw StateError(message);

void main() {
  final lessons = LiaisonCurriculumCatalog.all;
  if (lessons.length != 60) {
    fail('Expected 60 prepared liaison lessons, found ${lessons.length}.');
  }

  final expectedCounts = {'A1': 30, 'A2': 20, 'B1': 10};
  for (final entry in expectedCounts.entries) {
    final count = lessons.where((lesson) => lesson.level == entry.key).length;
    if (count != entry.value) {
      fail('Expected ${entry.value} ${entry.key} lessons, found $count.');
    }
  }

  final ids = lessons.map((lesson) => lesson.id).toSet();
  final progressIds = lessons.map((lesson) => lesson.progressId).toSet();
  if (ids.length != lessons.length || progressIds.length != lessons.length) {
    fail('Liaison lesson identifiers must be unique.');
  }

  for (final lesson in lessons) {
    if (lesson.phrase.trim().isEmpty ||
        lesson.sentence.trim().isEmpty ||
        lesson.passage.trim().isEmpty ||
        lesson.sentenceEnglish.trim().isEmpty ||
        lesson.passageEnglish.trim().isEmpty) {
      fail('Lesson ${lesson.id} contains empty learner content.');
    }
    if (LiaisonCurriculumCatalog.byId(lesson.id) != lesson ||
        LiaisonCurriculumCatalog.byProgressId(lesson.progressId) != lesson) {
      fail('Lesson ${lesson.id} cannot be reopened by its stored identity.');
    }
  }

  final a1 = LiaisonCurriculumCatalog.forLevel('A1');
  if (a1.any((lesson) => lesson.ruleType != LiaisonRuleType.obligatory)) {
    fail('A1 must teach only obligatory beginner liaison boundaries.');
  }

  if (LiaisonCurriculumCatalog.normalizeLevel('B2') != 'B1') {
    fail('B2 liaison practice must resolve to the advanced B1 catalog.');
  }

  print(
    'Liaison catalog verified: 60 lessons '
    '(A1 30, A2 20, B1/B2 10), unique persistence IDs, complete content.',
  );
}
