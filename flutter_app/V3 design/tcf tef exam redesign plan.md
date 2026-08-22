# V3 TCF / TEF Exam Preparation — Workspace and Attempt Wireframes

## Status

Proposal only. This plan defines the exam shell and the boundaries between
exam preparation and the existing Reading, Listening, Speaking, and Writing
engines.

## Product contract

Exam preparation is a measurable workspace, not four unrelated practice
buttons:

```text
Exam home
  → choose TCF Canada or TEF Canada
  → see level, section readiness, and recent attempts
  → choose a section or a timed mini-mock
  → read the task brief and rules
  → complete timed task
  → submit once / score once
  → review evidence and next action
  → return to Exam home with progress refreshed
```

The exam shell owns exam context, timing, attempt identity, and results. The
skill engines own their established interaction:

- Reading uses the approved Reading story/quiz surface.
- Listening uses the approved Spotify-like player and transcript behavior.
- Speaking uses the approved chat-first speaking route, with exam-specific
  task instructions and timing.
- Writing uses the writing task/editor and a separate saved submission.

The shell must not duplicate those engines or route a TCF/TEF learner into a
generic story or a generic speaking session without exam metadata.

## Current code and gaps

Current surfaces:

- `lib/screens/exam/exam_readiness_screen.dart` — TCF/TEF selector, level
  selector, Reading/Listening/Writing/Speaking actions, recent attempts.
- `lib/screens/exam/exam_practice_screen.dart` — document/audio/question flow
  for exam-style reading/listening QCM.
- `lib/screens/mocks/mocks_screen.dart` — speaking mock and result feedback.
- `lib/data/database/exam_practice_store.dart` — local attempt identity and
  completion fields.
- `lib/models/exam_practice.dart` — attempt and summary models.

Current gaps:

1. The exam home has section launch cards but not one coherent readiness
   picture.
2. Timed state and submitted state are not presented as a single attempt
   lifecycle across all four skills.
3. Recent attempts have limited section/result context.
4. Exam generation and skill routes need a strict `examName`, `levelBand`,
   `section`, and `attemptId` contract.
5. The current labels say “free preparation” but do not explain the difference
   between a warm-up, a timed section, and a mini-mock.

## Visual thesis

Use the V3 dark focused shell with a clear exam identity at the top, progress
bands rather than a tile grid, and a persistent bottom action only when the
current task has a safe submission. Gold marks the active section; green/red
are reserved for scored evidence.

## Screen 1 — Exam home

```text
┌──────────────────────────────────────┐
│ ‹  Exam preparation              ⋯  │
│                                      │
│ TCF CANADA                   [TEF ▾] │
│ Your plan · A2 · 20 min today       │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ READINESS                         │ │
│ │ 3 of 4 skills practiced          │ │
│ │ Reading   ●●●○   Listening ●●○○  │ │
│ │ Speaking  ●●○○   Writing   ●○○○  │ │
│ │ [Continue next section →]        │ │
│ └──────────────────────────────────┘ │
│                                      │
│ PRACTICE BY SECTION                 │
│ ┌──────────────┐ ┌──────────────┐  │
│ │ Reading      │ │ Listening    │  │
│ │ 12 min · A2  │ │ 10 min · A2  │  │
│ └──────────────┘ └──────────────┘  │
│ ┌──────────────┐ ┌──────────────┐  │
│ │ Speaking     │ │ Writing      │  │
│ │ 8 min · A2   │ │ 15 min · A2  │  │
│ └──────────────┘ └──────────────┘  │
│                                      │
│ RECENT ATTEMPTS                     │
│ A2 · Listening · 7/10 · Yesterday › │
└──────────────────────────────────────┘
```

The exam selector is a sheet or compact dropdown, not a separate screen. A
level change is explicit and starts new future attempts; it does not rewrite
completed history.

## Screen 2 — Section brief

```text
┌──────────────────────────────────────┐
│ ‹  TCF Canada · Listening        ⚑  │
│                                      │
│ LISTENING                            │
│ Understand the main idea and detail. │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ A2 · 10 minutes                  │ │
│ │ 10 questions · one replay        │ │
│ │ Scored on comprehension         │ │
│ └──────────────────────────────────┘ │
│                                      │
│ You will hear a short French audio, │
│ then choose one answer.             │
│ Translation is hidden during the    │
│ timed attempt.                      │
│                                      │
│ [Untimed warm-up] [Start timed →]   │
└──────────────────────────────────────┘
```

The brief states exactly what is timed, how many replays are allowed, and
whether translation or hints are available. A warm-up is an explicitly
different attempt type; it is not a fallback when generation fails.

## Screen 3 — Timed task shell

```text
┌──────────────────────────────────────┐
│ ×  Listening · 03 / 10          07:42│
│ ───────────────●───────────────────  │
│                                      │
│ QUESTION 3                           │
│ ┌──────────────────────────────────┐ │
│ │ ▶  Audio passage                 │ │
│ │    One replay remaining          │ │
│ └──────────────────────────────────┘ │
│                                      │
│ What does the speaker want to do?    │
│                                      │
│ ○  Change the appointment            │
│ ○  Confirm the appointment            │
│ ○  Cancel the reservation             │
│                                      │
│ [Flag question]                      │
│                                      │
│ [Save answer & Next →]               │
└──────────────────────────────────────┘
```

Rules:

- Timer is attempt-scoped and persists through the current task transition.
- The answer is written to the attempt before the next question appears.
- Closing asks whether to leave; it never submits or silently abandons.
- The exact French stimulus and answer key are stored with the attempt so the
  result remains reviewable if the generator is unavailable later.
- The timed surface never shows English translation unless that task contract
  explicitly permits it.

For Reading, replace the audio block with the document/paragraph block. For
Writing, replace choices with the editor and word/time counters. For Speaking,
open the shared live route with an exam task card and a strict timer.

## Screen 4 — Section review before submit

```text
┌──────────────────────────────────────┐
│ ‹  Review answers                    │
│                                      │
│ TCF · Listening · 10 questions       │
│                                      │
│ 01 ✓   02 ✓   03 ?   04 ✓   05 ⚑    │
│ 06 ✓   07 —   08 ✓   09 —   10 —    │
│                                      │
│ 2 unanswered · 1 flagged              │
│ You can return to a question while  │
│ time remains.                        │
│                                      │
│ [Return to flagged] [Submit section] │
└──────────────────────────────────────┘
```

If the timer expires, this screen becomes a locked submission confirmation and
the attempt is scored once. There is no second hidden submission.

## Screen 5 — Result and next step

```text
┌──────────────────────────────────────┐
│ ‹  Listening result                  │
│                                      │
│ TCF CANADA · A2                      │
│ 7 / 10 correct                       │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Evidence                         │ │
│ │ Main idea        3 / 4           │ │
│ │ Detail           2 / 3           │ │
│ │ Inference        2 / 3           │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Review 3 missed questions            │
│ Next focus: appointment vocabulary   │
│                                      │
│ [Review mistakes] [Next section →]   │
└──────────────────────────────────────┘
```

Results distinguish correctness from a CEFR estimate. A single short attempt
must not claim an official TCF/TEF score. The result can recommend vocabulary,
listening, speaking, or writing practice by linking to those canonical flows.

## Screen 6 — Exam history

```text
┌──────────────────────────────────────┐
│ ‹  Exam history                      │
│ [TCF ▾] [All sections ▾]             │
│                                      │
│ Aug 22 · A2                         │
│ Listening · 7/10 · Review ›          │
│                                      │
│ Aug 20 · A2                         │
│ Speaking · 4:12 · View transcript › │
│                                      │
│ Aug 18 · A1                         │
│ Reading · 8/10 · Review ›            │
└──────────────────────────────────────┘
```

The history route reads `ExamPracticeStore.summaries()` and opens the saved
attempt. It must not generate a new task when a row is tapped.

## Data contract

```text
ExamAttempt
  id, examName, levelBand, section, attemptType
  taskSetId, startedAt, expiresAt, submittedAt
  answers[], flaggedQuestionIds[], score, rubricEvidence, status

Exam home
  → readiness aggregates by examName + levelBand + section
  → recent history indexes by attemptId
```

The existing `ExamPracticeStore` is a useful starting point, but the next
proposal must add the missing section/attempt metadata without changing the
meaning of existing rows. Existing story payloads remain reviewable; new
listening, writing, and speaking payloads use explicit skill envelopes.

## TEF / TCF content rules

- TCF and TEF remain separate selectors with separate task instructions.
- A1/A2 preparation is not an official exam score claim; show “practice
  estimate” language.
- A1 tasks use concrete notices, schedules, short exchanges, and direct
  choices. B1/B2 tasks introduce inference, viewpoint, register, and linked
  arguments.
- Speaking Section A/B and Writing task types must be represented in the brief
  before recording or editing begins.
- Timed tasks never downgrade to an untimed generic task when a provider or
  storage request fails.

## Mobbin references

- [Duolingo timed answer with immediate feedback](https://mobbin.com/screens/9e684a14-b781-4560-a472-f525c8655a64) — compact progress, task, answer state, and bottom continuation.
- [Duolingo rapid-review result state](https://mobbin.com/screens/a8db96b1-31d0-46aa-bf74-0ca30e8e3b44) — clear completion summary before continuing.
- [Duolingo course/section overview](https://mobbin.com/flows/047e252c-3bf3-4c33-b3b2-c5dd6065d1d4) — reference for grouping progress into a path, not a tile dump.

## Acceptance checklist

- [ ] One Exam home supports TCF and TEF without duplicating section logic.
- [ ] Every attempt has a stable ID, exam, level, section, timer state, and
      persisted result.
- [ ] Reading, Listening, Speaking, and Writing reuse the approved skill
      engines and return to one exam result contract.
- [ ] Timer expiry and manual submit each produce exactly one result.
- [ ] Recent attempts open saved review, never a new generated attempt.
- [ ] Practice estimate language is used instead of an official score claim.
- [ ] A1–B2 content changes in task complexity and feedback, not only a label.
- [ ] Provider, storage, or scoring failure is visible and actionable; no
      hidden fallback task is shown.

