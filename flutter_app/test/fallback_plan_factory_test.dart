import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/planning/fallback_plan_factory.dart';

const _framework = CompetencyFramework(
  frameworkVersion: 'test',
  curriculumVersion: 'test',
  competencies: [
    Competency(
      id: 'competency-1',
      kind: CompetencyKind.lexical,
      title: 'Word',
      description: 'A word',
      difficultyBand: 'A2',
      prerequisiteIds: [],
      curriculumVersion: 'test',
    ),
  ],
  mappings: [
    ContentCompetencyMapping(
      id: 'mapping-reading',
      contentItemId: 'content-reading',
      competencyId: 'competency-1',
      role: ContentMappingRole.practises,
      modality: PerformanceModality.readingRecognition,
      weight: 0.8,
      curriculumVersion: 'test',
    ),
    ContentCompetencyMapping(
      id: 'mapping-live',
      contentItemId: 'content-live',
      competencyId: 'competency-1',
      role: ContentMappingRole.assesses,
      modality: PerformanceModality.spontaneousSpeaking,
      weight: 0.9,
      curriculumVersion: 'test',
    ),
  ],
);

void main() {
  test('excludes network-only spontaneous-speaking tasks', () {
    final plan = const FallbackPlanFactory().build(
      framework: _framework,
      availableMinutes: 60,
    );

    expect(
      plan.tasks.every((t) => t.modality != PerformanceModality.spontaneousSpeaking),
      isTrue,
    );
    expect(plan.tasks, isNotEmpty);
  });

  test('never exceeds the available time budget', () {
    final plan = const FallbackPlanFactory().build(
      framework: _framework,
      availableMinutes: 5,
    );

    expect(plan.totalMinutes, lessThanOrEqualTo(5));
  });

  test('is deterministic for the same inputs', () {
    final first = const FallbackPlanFactory().build(
      framework: _framework,
      availableMinutes: 60,
    );
    final second = const FallbackPlanFactory().build(
      framework: _framework,
      availableMinutes: 60,
    );

    expect(
      first.tasks.map((t) => t.contentItemId),
      second.tasks.map((t) => t.contentItemId),
    );
  });
}
