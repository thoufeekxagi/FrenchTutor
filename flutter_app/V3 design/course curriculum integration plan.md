# V3 course curriculum integration plan

## Purpose

The adaptive course is the shared source of truth for the first learning path.
Home, Course, Practice, Speaking, Listening, Reading, Writing, and Review may
render different experiences, but they must open the same `contentKey` and
preserve the same sequence and completion state.

## First twenty sessions

The first block is intentionally predictable so a new learner is never asked
to wait for a random lesson or dropped into an advanced task.

| Sessions | Unit | Learning path |
| --- | --- | --- |
| 1–5 | Unit 1 — Alphabet & sound foundations | Alphabet → vowels → consonants → accents → sound and meaning |
| 6–10 | Unit 2 — First words & introductions | Vocabulary → grammar → reading → listening → speaking |
| 11–15 | Unit 3 — Everyday needs | Café/food vocabulary → polite requests → menu reading → order listening → café speaking |
| 16–20 | Unit 4 — Integrated beginner conversations | Numbers/time vocabulary → questions → signs/schedules → directions listening → integrated speaking/review |

Each session has one primary skill and explicit supporting skills. The content
engine receives the same session context, CEFR level, grammar focus, learning
phase, and success criteria, so the generated lesson stays in the same scene
instead of becoming an unrelated exercise.

## CEFR control

- **A1:** fixed phrases, present tense, one or two short sentences, concrete
  personal and daily situations.
- **A2:** past and near-future forms, simple reasons, several linked ideas.
- **B1:** connectors, time frames, supported opinions, organized responses.
- **B2:** nuance, reformulation, register, and precise independent responses.

The path structure stays the same across levels, but the grammar and success
criteria are level-specific. A higher level reviews the sound foundations with
more natural connected speech rather than receiving an A1-only explanation.

## Generation and persistence rules

1. Generate the first twenty session specifications locally and immediately.
2. Generate rich lesson payloads only when a learner opens a session.
3. When five or fewer sessions remain, append the next twenty specifications so
   the next lesson is ready without a visible generation wait.
4. Repair missing sequence numbers before rendering a plan. This restores Unit
   1 or Unit 2 when older data contains Unit 4 but an earlier session is absent.
5. Reconcile completion by the exact adaptive `contentKey`, never by row count.
   Completed lessons remain visible with a checkmark.
6. Upgrade unfinished Unit 1–4 rows in place when an existing installation
   opens the plan. Stable ids, statuses, and progress keys are preserved;
   completed rows remain historical records.
7. Keep generation errors explicit. There is no silent provider or lesson
   fallback that can change the meaning of a session.

## Entry points

- Practice → Speaking opens `SpeakingHubScreen`, which reads the adaptive plan.
- Speaking shows the Unit 1 foundation rows as well as the speaking rows; the
  unit title is dynamic, not hardcoded to “The Basics”.
- Course and roadmap screens read the same adaptive sessions and completion
  keys.
- Home “next session” must navigate to the existing adaptive `contentKey` and
  must not create a new AI lesson.

## Acceptance checks

- A new A1 plan visibly starts with alphabet and sound foundations.
- Sessions 6–10 are first words and introductions; 11–15 are everyday needs;
  16–20 are integrated conversations.
- A2, B1, and B2 keep the same unit order but receive their own grammar and
  success criteria.
- Completing session 6 marks only session 6 complete.
- Removing or corrupting an early row repairs the missing sequence on the next
  plan read without duplicating later sessions.
- Practice → Speaking and Course → Speaking render the same session titles,
  order, and completion state.
- No Flutter build, simulator, or device run is part of source verification.
