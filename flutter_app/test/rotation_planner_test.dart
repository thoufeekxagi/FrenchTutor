import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/content_service.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/data/database/plan_store.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/planning/rotation_planner.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ContentService.shared.preload);

  const planner = RotationPlanner();

  test('modality cycles through the fixed rotation order', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final planStore = PlanStore(db);
    final learningStore = LearningStore(db);

    for (var i = 0; i < rotationOrder.length; i++) {
      final result = planner.buildNext(
        planStore: planStore,
        learningStore: learningStore,
        content: ContentService.shared,
        localDate: '2026-07-${21 + i}',
        availableMinutes: 20,
        learnerLevel: 'a1',
      );
      expect(result.plan.tasks.first.modality, rotationOrder[i]);
      planStore.savePlan(result.plan);
    }

    // The rotation wraps back to the start after a full cycle.
    final wrapped = planner.buildNext(
      planStore: planStore,
      learningStore: learningStore,
      content: ContentService.shared,
      localDate: '2026-08-01',
      availableMinutes: 20,
      learnerLevel: 'a1',
    );
    expect(wrapped.plan.tasks.first.modality, rotationOrder.first);
  });

  test('excludes already-seen content until the bank is exhausted', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final planStore = PlanStore(db);
    final learningStore = LearningStore(db);

    final first = planner.buildNext(
      planStore: planStore,
      learningStore: learningStore,
      content: ContentService.shared,
      localDate: '2026-07-21',
      availableMinutes: 20,
      learnerLevel: 'a1',
    );
    final firstContentId = first.plan.tasks.first.contentItemId;
    learningStore.setLessonStatus(firstContentId, 'completed');
    planStore.savePlan(first.plan);

    // Force the SAME modality again (skip 5 plans forward to wrap back to
    // listening) and confirm the just-seen item isn't picked again while
    // other unseen listening exercises remain.
    for (var i = 0; i < rotationOrder.length - 1; i++) {
      planStore.savePlan(
        planner
            .buildNext(
              planStore: planStore,
              learningStore: learningStore,
              content: ContentService.shared,
              localDate: '2026-07-${22 + i}',
              availableMinutes: 20,
              learnerLevel: 'a1',
            )
            .plan,
      );
    }
    final secondListening = planner.buildNext(
      planStore: planStore,
      learningStore: learningStore,
      content: ContentService.shared,
      localDate: '2026-07-28',
      availableMinutes: 20,
      learnerLevel: 'a1',
    );
    expect(secondListening.plan.tasks.first.modality, PerformanceModality.listeningRecognition);
    expect(secondListening.plan.tasks.first.contentItemId, isNot(firstContentId));
  });

  test('reading/vocab slot batches several words, not just one', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final planStore = PlanStore(db);
    final learningStore = LearningStore(db);
    // Advance to index 1 (readingRecognition) in the rotation.
    planStore.savePlan(
      planner
          .buildNext(
            planStore: planStore,
            learningStore: learningStore,
            content: ContentService.shared,
            localDate: '2026-07-21',
            availableMinutes: 20,
            learnerLevel: 'a1',
          )
          .plan,
    );
    final vocabDay = planner.buildNext(
      planStore: planStore,
      learningStore: learningStore,
      content: ContentService.shared,
      localDate: '2026-07-22',
      availableMinutes: 20,
      learnerLevel: 'a1',
    );
    expect(vocabDay.plan.tasks.first.modality, PerformanceModality.readingRecognition);
    expect(vocabDay.plan.tasks.length, vocabBatchSize);
    expect(vocabDay.mission.steps.length, vocabBatchSize);
  });

  test('buildMissionFor deterministically reconstructs the same mission', () {
    final a = planner.buildMissionFor(
      contentItemIds: const ['l01'],
      modality: PerformanceModality.listeningRecognition,
      learnerLevel: 'a2',
    );
    final b = planner.buildMissionFor(
      contentItemIds: const ['l01'],
      modality: PerformanceModality.listeningRecognition,
      learnerLevel: 'a2',
    );
    expect(a.title, b.title);
    expect(a.scenario, b.scenario);
    expect(a.promptContext, b.promptContext);
    expect(a.levelBand, b.levelBand);
  });
}
