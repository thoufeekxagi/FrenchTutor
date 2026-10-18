import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/tests/v3_exam_sets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final level in V3ExamSets.levels) {
    for (final skill in V3ExamSets.skills) {
      test('$level $skill set is complete and answerable', () async {
        final lesson = await V3ExamSets.load(level, skill);
        expect(lesson.id, 'exam-$level-$skill');
        expect(lesson.steps.length, inInclusiveRange(5, 7));
        final ids = lesson.steps.map((s) => s.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'unique step ids');
        var questions = 0;
        for (final step in lesson.steps) {
          switch (step) {
            case V3ChooseStep s:
              questions++;
              expect(s.options.length, 4);
              expect(s.options.toSet().length, 4, reason: s.id);
              expect(s.answer, inInclusiveRange(0, 3));
              expect(s.explain, isNotEmpty);
              expect(s.prompt, isNotEmpty);
            case V3ListenStep s:
              questions++;
              expect(s.fr.trim(), isNotEmpty);
              expect(s.options.length, 4);
              expect(s.options.toSet().length, 4, reason: s.id);
              expect(s.answer, inInclusiveRange(0, 3));
              expect(s.explain, isNotEmpty);
            case V3PhraseStep s:
              expect(s.fr, isNotEmpty);
              expect(s.en, isNotEmpty);
            case V3ExplainStep s:
              expect(s.body, isNotEmpty);
            default:
              break;
          }
        }
        expect(questions, greaterThanOrEqualTo(2));
      });
    }
  }

  test('listening and reading have five questions at every level', () async {
    for (final level in V3ExamSets.levels) {
      for (final skill in ['listening', 'reading']) {
        final lesson = await V3ExamSets.load(level, skill);
        final q = lesson.steps
            .where((s) => s is V3ChooseStep || s is V3ListenStep)
            .length;
        expect(q, 5, reason: '$level $skill');
      }
    }
  });

  test('the correct answers are spread over all four positions', () async {
    final positions = <int>{};
    for (final level in V3ExamSets.levels) {
      for (final skill in V3ExamSets.skills) {
        final lesson = await V3ExamSets.load(level, skill);
        for (final s in lesson.steps) {
          if (s is V3ChooseStep) positions.add(s.answer);
          if (s is V3ListenStep) positions.add(s.answer);
        }
      }
    }
    expect(positions, {0, 1, 2, 3});
  });
}
