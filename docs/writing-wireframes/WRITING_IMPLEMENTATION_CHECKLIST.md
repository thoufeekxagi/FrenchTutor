# Writing implementation checklist

Updated: 2026-08-23

This is the source-of-truth checklist for the independent Writing experience.
Writing must not open Vocabulary, Speaking, or the old one-shot editor by
accident. It uses the shared black/gold design tokens and remains image-free by
product decision.

## Entry points

| Entry | Route | Expected behavior |
|---|---|---|
| Practice → Writing | `WritingLabScreen` | Opens the ready Writing home immediately; no artwork generation. |
| Writing home → Continue | `WritingWorkshopScreen` | Opens the next saved task for the learner's current level. |
| Writing home → Words/Sentences/Free writing | `WritingWorkshopScreen` | Opens the first ready task in that mode from the independent writing bank. |
| Writing home → TCF / TEF writing | `ExamReadinessScreen` | Keeps exam selection and level selection separate from beginner lessons. |
| Writing home → Personalized task | `WritingLabScreen` generation path | Explicit network action; saves the generated task before opening it. |
| Recent generated prompt | `WritingWorkshopScreen` | Reopens the saved task; it does not generate a replacement. |

## Ready curriculum

`WritingCurriculumCatalog` is the fast first-run queue:

- A1: everyday word recognition, short sentence construction, then short messages.
- A2: word recognition, sentence construction, messages, then short free writing.
- B1/B2: independent typed writing with level-specific opinion tasks.
- Completion is stored with the existing `lessonStatus` store. The next card is
  calculated from the first incomplete task, so the learner never waits for a
  model before the next lesson is available.

## Workshop state machine

### Word and sentence tasks

`Brief → Build → Review`

1. Brief shows the learner-facing French instruction and English support.
2. Build shows a fixed word bank and the learner's selected order.
3. Check compares the selected tokens with the task's exact target tokens.
4. Correct order opens the green Review state in the same workshop.
5. Finish lesson returns `true`; the Writing home marks the task complete.
6. Wrong order stays in Build and shows an explicit correction message.

### Message and free-writing tasks

`Brief → Build → Draft → Review → Rewrite`

1. Build offers optional useful-word chips but never writes the answer.
2. Draft is the learner's own French response.
3. Submit calls the existing structured writing grader.
4. Review keeps the exact submission, corrections, strengths, improved version,
   and next steps together in the same writing flow.
5. Rewrite asks for one focused correction and checks it with the existing
   micro-writing grader.
6. Finish workshop returns `true`; feedback is already persisted in the
   existing writing submission store.

## Exam contract

Exam generation is deliberately stricter than normal personalized practice.
The model must return a recognized section. The service then normalizes the
official contract and rejects an unknown/missing section rather than silently
turning it into a generic task.

### TCF Canada

- One generated task is tagged `TCF Task 1`, `TCF Task 2`, or `TCF Task 3`.
- Task 1: 60–120 words.
- Task 2: 120–150 words.
- Task 3: 120–180 words.
- The written-expression paper is 60 minutes.

### TEF Canada

- One generated task is tagged `TEF Section A` or `TEF Section B`.
- Section A: continue an article, at least 80 words, 25 minutes.
- Section B: express and justify a point of view, at least 200 words, 35 minutes.

The workshop displays the section, time, and word contract on the Brief screen
and includes the same data in the tutor context. A1/A2 exam training can use
simplified language, but it does not weaken the official exam word contract.

## Persistence rules

- Static curriculum tasks are saved through the existing lesson-status store.
- Generated tasks are saved through `GeneratedWritingTaskStore` before the
  workshop opens and are hydrated from Supabase on the next visit.
- Generated writing does not request or upload a cover image.
- Submissions and structured feedback use the existing writing submission store.
- A provider error is shown as an error. No alternate provider or alternate
  activity is silently selected.

## Lightweight verification

Run only source-level checks for this feature:

```sh
dart format --output=none --set-exit-if-changed \
  flutter_app/lib/models/content_models.dart \
  flutter_app/lib/data/writing_curriculum_catalog.dart \
  flutter_app/lib/screens/labs/writing_lab_screen.dart \
  flutter_app/lib/screens/lessons/writing_workshop_screen.dart \
  flutter_app/lib/screens/exam/exam_readiness_screen.dart \
  flutter_app/lib/services/lesson_agent_service.dart
git diff --check
```

Do not run a Flutter build or simulator as part of this handoff.
