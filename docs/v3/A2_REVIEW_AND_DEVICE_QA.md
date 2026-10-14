# A2 reviewer status and device QA

This note is the handoff for the complete A2 stage. It tells a future agent
what was inspected, what passed locally, what still needs a French/TCF expert,
and how to exercise the exported A2 course on the owner's iPad without
touching real learner progress.

## Current A2 package

- Twelve authored units, in order, from "A week in my life" to the changing-week
  capstone. The complete map is in `ROADMAP.md` and in the reviewer PDF.
- 570 planned new word entries across the twelve units. This is a course
  planning count, not an official CEFR list or proof of level attainment.
- The scoped export currently contains 173 lessons, 1,820 steps, 516 generated
  vocabulary checks and 12 stories. `--a2-only` preserves the other stages.
- The reviewer copy is
  `docs/v3/book/ParleSprint_A2_Reviewer_Draft.pdf` (152 pages), with source HTML
  beside it. It includes all units, answer key, listening scripts, writing and
  speaking models, and a 668-entry vocabulary/phrase index.
- A2 is an independent learning stage, not a complete official TCF Canada
  practice pack and not a promise of a TCF or CLB/NCLC score.

## What the audit changed and checked

This was a review and refinement pass over the existing A2 sources; it did not
replace the syllabus or create a PDF-first course. Corrections focused on
natural examples and clear progression into past narration, especially the
irregular past participles and selected *être* verbs in Unit 3, the background
versus completed-event contrast in Unit 4, and awkward or ambiguous examples
and lines in Units 2, 5, 6, 8, 11 and 12. The book checker and scoped exporter
were adjusted so A1/A2 work can be validated without importing unfinished or
unrelated B1/B2 source files. The A2 exporter merges its lessons and stories
into the existing indexes and leaves the B1/B2 entries unchanged.

The course starts with short connectors, then builds past tense in steps:
regular *passé composé* with *avoir*; high-frequency irregular forms and a
starter set with *être*; then *imparfait* background/habit contrasted with
completed events. Later units move through future plans, comparisons, relative
pronouns, object pronouns, *y*, *en*, and polite instructions/requests before
the capstone. Grammar is explicit and briefly explained in English, followed
by examples, comprehension, retrieval and a changed-context task.

Local verification completed on 2026-10-13:

1. `python3 content/tcf/book/check_book.py`: 27 chapters (12 A2), 3,340 known
   tokens, 296 example notes, zero errors and zero ledger warnings.
2. `python3 content/tcf/book/export_app.py --a2-only`: 173 lessons, 1,820
   steps, 516 generated checks and 12 stories.
3. `python3 content/tcf/tools/validate.py`: 733 lesson files scanned, zero
   errors and one expected warning for the hidden development sample.
4. `cd flutter_app && tool/check.sh --quick`: passed format, analyzer gate,
   v3 testability lint and content validation.
5. `cd flutter_app && flutter test --no-pub test/v3_*_test.dart
   test/mic_echo_gate_test.dart`: all 266 tests passed. These include simulated
   phone and iPad portrait/landscape layouts at normal and double text size.
6. The 152-page PDF was built from the same authored chapter sources and
   visually inspected as contact sheets plus selected full-size pages. Text
   extraction confirmed all twelve units, the answer-key section and index.
7. B1/B2 generated lesson and story hashes and their course-index order were
   captured around the A2-only export and remained unchanged.

These checks do not replace a real device run, a human French-language review,
or listening to the actual tutor voice. Do not describe those as completed.

## French and TCF review still required

`content/tcf/REVIEW_NEEDED.md` is the authoritative item list. Before calling
the course release-ready, a fluent French speaker and TCF Canada specialist
should review all A2 units, not only the corrected examples. Prioritize:

- grammar descriptions and every agreement, pronoun and tense example;
- the U3 *être* auxiliary set and U4/U5 *passé composé* versus *imparfait*
  distinction;
- sound guides, spoken rhythm, idiom, register, and English lines for all
  entries, dialogues, stories and models;
- Ontario/Canadian rental, transit, grocery, health-service, work and delivery
  terms; ensure fictional health scenes do not read as medical advice;
- every listening/reading/checkpoint answer against its text or script,
  including whether a distractor could also be correct;
- the A2 workload, grammar pace, and transfer tasks for an adult coming from
  A1 who studies on an iPad beside a notes app;
- whether the TCF-style corner is correctly labelled as original, scaffolded
  practice rather than official-length or exam-equivalent practice.

Record corrections against unit, lesson and item IDs. Apply corrections to the
canonical chapter sources, then rerun the content checks, Flutter tests, and
PDF build. Never edit generated lesson JSON directly.

## Connected-device course walk

Run only when the owner has connected, trusted and unlocked the iPad or iPhone,
enabled Developer Mode, and confirmed that the current device is in the signing
profile. Use the actual device ID from `tool/device.sh list`; the iPad ID in the
current testing guide is `51a217780d70704c1f8e62e8000df51be95376a4`.

From `flutter_app/`, run the A2 course in three batches. Each batch launches a
debug integration build, automatically answers each lesson from its authored
answer key, checks each step, verifies a perfect score, and confirms completion
was recorded. It does not tap speaker buttons or call Gemini Live. `E2E_SHELL`
uses namespaced `e2e_` progress keys, so it does not erase the learner's real
progress. The course walk also grants the debug-only test unlock.

```sh
cd flutter_app
DEVICE=51a217780d70704c1f8e62e8000df51be95376a4

E2E_DEFINES='--dart-define=E2E_SHELL=true --dart-define=E2E_ONLY=a2-u01,a2-u02,a2-u03,a2-u04' \
  tool/e2e.sh integration_test/v3_course_walk_test.dart "$DEVICE" 3600
```

Repeat for Units 5–8 and 9–12 by replacing the `E2E_ONLY` value with:

```text
a2-u05,a2-u06,a2-u07,a2-u08
a2-u09,a2-u10,a2-u11,a2-u12
```

Each ID is a prefix filter and preserves course order. Set a suitable longer
timeout if a batch is still progressing; if a batch fails, inspect its
`artifacts/e2e/run.log`, `result.txt`, `probe.json` and timeout screenshot
before retrying. `tool/e2e.sh` replaces `artifacts/e2e` on each run, so save
the previous batch's evidence elsewhere before starting the next one. Follow
the two-failed-attempts stop rule in `AGENT_RULES.md`.

Then walk the A2 stories through the story reader and quiz:

```sh
E2E_DEFINES='--dart-define=E2E_SHELL=true --dart-define=E2E_FAKE_AUDIO=true --dart-define=E2E_STORY_ONLY=a2-' \
  tool/e2e.sh integration_test/v3_story_test.dart "$DEVICE" 1800
```

The story test checks reading, word cards, translations, playback controls,
saved words, quizzes and completion with fake audio. It does not prove the real
French voice. After the debug integration runs, reinstall and launch the
production build using section 7 of `FAST_ITERATION_TESTING.md`; the course walk
replaces the installed release app with a debug build. Do not uninstall the
app.

## Human, learner-side smoke test

After installing the release build, use Split View with ParleSprint on the
left and a notes app on the right. Try one early lesson, one past-tense lesson,
one Canadian-life unit, and the capstone (suggested: U1, U3/U4, U6/U7, U12).

- Can you tell what to do next without reading a developer explanation?
- Does each lesson fit in portrait, landscape and Split View without tiny or
  clipped text? Can you take notes without obscuring the lesson?
- Are the grammar explanation, example and exercise connected? Can you answer
  with notes closed and use the same pattern in a new example?
- Do correct and incorrect answers give clear feedback? Do Check, Continue,
  Previous, exit and Resume behave as expected?
- Do the story, reading and listening materials sound like plausible everyday
  situations? Can you understand what the prompt asks before seeing an answer?
- Do real tutor speech and lesson playback sound natural at a useful volume?
  Check that the microphone stays closed while the app is speaking, including
  the playback tail and Bluetooth route.

Report issues with the unit, lesson title/ID, exact words, screen orientation,
whether the app was in Split View, and a screenshot or short recording when
useful. That makes the correction reproducible.
