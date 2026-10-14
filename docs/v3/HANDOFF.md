# V3 handoff: the plan, the style, the decisions, what is next

For the next agent (Codex, Claude, Devin, anyone). Read `README.md` first, then
this file. It records what ParleSprint v3 is, how we decided things, how the
screens are designed, and the ordered work that remains. Keep it current: every
handoff updates the "Current state" block at the bottom.

## 1. The mission

ParleSprint teaches French to adults from zero for **TCF Canada**, Canadian
immigration and citizenship (target NCLC 7). The owner is learning from it
every day on an iPad (often with a notes app beside it in Split View) and wants
other people to learn from it too. Quality must not drop. The owner's words:
the app is the product; the book is only the source of truth that makes
writing and checking fast.

The path a learner follows, always in this order: **sounds and spelling, then
vocabulary, then phrases and sentence building, then grammar (how words
connect), then dialogues and stories, then listening, speaking, reading and
writing, then TCF-style practice.** A1, A2, B1, B2.

Gemini Live (the tutor, voiced as Marie, Julien, Camille or Mathieu) can support
pronunciation, explanations and speaking practice. The course does not promise
that AI accelerates learning. The tutor is never the source of the curriculum;
the curriculum is authored and validated.

## 2. Decisions already made (do not reopen without the owner)

1. **Deterministic, hand-authored course.** No runtime AI lesson generation, no
   GPT/OpenRouter lesson building. Every lesson, story and question is written
   by an agent as data and checked. Details: `LESSON_PIPELINE.md`.
2. **The book is the master text, the app is the product.** Chapter files in
   `content/tcf/book/chapters/` produce both the PDF and the app lessons.
   Generated app files are never edited by hand.
3. **Cumulative vocabulary and Canadian context** in every unit. Every word
   studied has an example sentence (enforced).
4. **Lesson audio = live tutor speech.** Speaker buttons ask the chosen tutor
   to say the exact line on one warm connection, as the old vocabulary lessons
   did. No saved clips for lesson words, so switching tutor switches every
   voice. A pre-made catalog is a possible later optimisation, per voice.
   (`MARIE_TUTOR.md`)
5. **Marie is inline**: phone button, panel, response pill, Mute, Skip. Never a
   full-screen route. She listens first and is not fenced to the card.
6. **The tutor never hears herself** (hard rule). `MicEchoGate`.
7. **One progress rule.** `V3Progress` keeps the furthest step reached
   (frontier), which only moves forward. Going back, reviewing and replaying
   never lower it. Resume means "where I really got to". (`AGENT_RULES.md` s9)
8. **One design everywhere**: Inter only, V3 primitives, semantic tokens, left
   aligned content, readable column on wide screens, no gamification chrome.
   (`DESIGN_SYSTEM.md`, enforced by `screen_map.py --check`)
9. **iPhone and iPad from one build.** Same bundle id `com.thoufeekx.frenchtutor`.
10. **Tests never touch real progress**: debug test keys are prefixed `e2e_`.

## 3. Where things are

```
content/tcf/                      course source (book chapters, checkers, exporter), REVIEW_NEEDED.md
docs/v3/                          all v3 docs, the PDF, design mockups
flutter_app/lib/v3/
  onboarding/                     animated blue/white greeting, split TCF value screens, optional date/reminders, level, account gate, optional post-sign-in Marie practice
  shell/                          four-tab shell: Learn, Marie, Tests, Me
  learn/                          Learn tab: Today, Path, Stories
  lesson/                         lesson model, course loader, V3Progress, lesson player, V3Speaker
  story/                          story model, store, audio, reader, stories panel
  marie/                          V3MarieSession (live and fake), dock, pill, transcript sheet
  me/, tests/                     Me tab and Tests tab (Tests still opens the old exam screen)
  ui/                             V3 primitives (type, button, option card, pressable, segments, width)
flutter_app/lib/services/         Gemini Live service, inline call controller, audio, mic echo gate
flutter_app/lib/prompts/          live prompts (compactLessonCoach)
flutter_app/test/                 unit and widget tests (fast, no phone)
flutter_app/integration_test/     on-device tests (probe based)
flutter_app/tool/                 check.sh, e2e.sh, e2e_all.sh, device.sh, screen_map.py, analyze_gate.py
.devin/skills/                    project skills for the Devin CLI agent
```

`docs/v3/SCREEN_MAP.md` is generated (`python3 flutter_app/tool/screen_map.py`).
It lists every screen file and its tappable keys.

## 4. How the UI is designed

Screen contract first (comment at the top of the screen file): who arrived and
why, what they must understand, exactly one primary action, success state, and
what the screen must not contain. Then build from existing primitives.

**Launch and onboarding** (`lib/v3/onboarding/v3_onboarding_flow.dart` has the
exact steps): the native blue logo launch is followed by a white/blue animated
greeting, then separate course, TCF goal/skills, and Marie screens. The short
setup asks for an optional exam date, the current A1–B2 level, and optional
reminder days/time. Consent and account gates follow; after sign-in, learners
can try the optional three-minute Marie practice. No extra profile questions,
fake progress, or scores. The existing onboarding device test still targets
the former screen order and needs a probe-based update before it can verify
this flow.

**Shell**: four tabs, Learn, Marie, Tests, Me. Light by default, Dark toggle in
Settings.

**Learn** (`lib/v3/learn/v3_learn_screen.dart`): segments Today, Path, Stories.
Today shows the exam countdown (if a date is set), one hero card with exactly
one action ("Start lesson" or "Resume lesson", with the step), a real progress
line ("N of M lessons"), and a way into Stories. Path lists units; an
unfinished lesson with progress asks Resume or Review from the start; a
finished lesson says "tap to replay".

**Lesson player** (`lesson/v3_lesson_player.dart`): step segments across the
top, close, and the Marie phone button. One instruction per step, large
answers, a bottom feedback bar (green or red with the explanation), and a
Previous button beside the single dominant Continue. While reviewing, a line
says where real progress is and offers "Go to step N". Step types: explain,
word, phrase, table, choose, listen (one play, like the TCF).

**Stories** (`lib/v3/story/`): no images. Editorial reading type, sentence
blocks with optional English, a small word card above the tapped word (meaning,
optional spoken word), a floating dock for play, replay, speed and stop, tabs
Story, Quiz, Words. Mockup: `docs/v3/design/story_reader_redesign.png`.

**Marie in lessons** (`lib/v3/marie/`): phone button, a compact panel above
Continue with status, Skip, Mute, End, and a pill with her last words (three
lines at most, tap for the whole conversation). Sheets use the same handle,
radius and spacing as the rest.

**iPad**: `V3Width` limits content to a readable left-aligned column; layouts
are checked on iPad portrait and landscape in the size matrix (see
`FAST_ITERATION_TESTING.md`). Still to do for iPad: keyboard and Pencil
friendly writing areas, and a proper two-pane layout if it earns its place.

Design values, the palette, and the lint that enforces them: `DESIGN_SYSTEM.md`.
Evidence-based rules and the screen list: `UI_STRUCTURE.md`.

## 5. The working method (how the quality was kept)

1. Evidence before action: look at the source, the probe, the screenshot. No
   assumed buttons.
2. Smallest change that reuses a primitive. One concern per commit.
3. Cheapest test first (`FAST_ITERATION_TESTING.md`). Size matrix on four
   screen sizes at two text scales. Fakes for anything that costs money.
4. Audit your own work: re-solve every question blind, recompute every price,
   read dialogues for continuity.
5. Be honest in reports: say what was not run (for example the device tests
   that failed to launch) and why.
6. Two failed attempts at the same problem: stop and report facts.
7. Do not reformat unrelated files. Never push unless asked. Never commit
   secrets.

## 6. Ordered backlog with acceptance criteria

| # | Work | Done when |
|---|---|---|
| 1 | **Complete: cross-level content and export audit, including B2 vocabulary expansion** | complete; all four authored levels pass their available source/export validators |
| 2 | **Inline Marie in the story reader** | `V3MarieSession` in the reader, narration and call share one socket, tests with the fake |
| 3 | **Review (spaced repetition)** over words learned, missed and saved | Learn shows a real review card; nothing invented; unit tests for the scheduler |
| 4 | **TCF mock engine** | real timers, one-play audio, 39-question sets, estimate labelled as an estimate |
| 5 | **Writing and speaking feedback** | one concise correction, one better version, one reason; no invented scores |
| 6 | **A1 mini mocks** after Units 5, 10, 14 | 10 listening and 10 reading in real format |
| 7 | **Course-wide progression, review and prerequisite design** | A1–B2 pacing and mastery gates are explicit; review scheduling adapts to learner evidence |
| 8 | **Progress sync** between devices | account-based; reinstall keeps progress |
| 9 | **Fluent French speaker review** | `REVIEW_NEEDED.md` items confirmed with name and date |
| 10 | **App Store update** | screenshots and notes match the TCF-only app; no claim of affiliation; Restore, Terms, Privacy, account deletion, AI consent kept |
| 11 | iPad polish: keyboard and Pencil writing areas | verified on the iPad in portrait, landscape and Split View |
| 12 | Remove legacy generation code (OpenRouter lesson builders) once unreachable | nothing in v3 can trigger it |

## 7. Division of work (suggested, adjust as the owner prefers)

| Work | Needs | Good fit |
|---|---|---|
| Writing units, checkers, exporter, PDF, docs | the Mac, Python, Chrome; no phone | any agent (Codex, Claude, Devin) |
| Flutter UI and logic with tests on the Mac | Flutter, no phone | any agent |
| On-device tests, release builds, install on the iPad and iPhone | Xcode signing, devices, `devicectl` | an agent with device access (Devin CLI did this so far) |
| Listening to audio, judging pronunciation and tone, French review | a human | the owner or a fluent speaker |

Take-over rule: one agent works in an area at a time. Before starting, run
`git log --oneline -10`, read the "Current state" block below, and run
`tool/check.sh --quick`. Before stopping, update the block and `ROADMAP.md`,
and say what you could not verify. Commit only when the owner has asked for a
commit; never push without an explicit request.

## 8. Copy-paste prompt for another agent

```
You are continuing ParleSprint (TCF Canada French app) in this repo, branch tcf-v3.
Read docs/v3/README.md, then docs/v3/HANDOFF.md, docs/v3/AGENT_RULES.md,
docs/v3/FAST_ITERATION_TESTING.md and docs/v3/LESSON_PIPELINE.md before changing anything.
Before doing A2 work, read `docs/v3/A2_REVIEW_AND_DEVICE_QA.md`. All twelve
A2 units exist; do not start rewriting or expanding them without a concrete
review finding. The current handoff is to get a French/TCF specialist review,
then complete the connected-device A2 walk when the owner connects the iPad.
Keep corrections in canonical chapter sources, use `export_app.py --a2-only`,
and rerun the checks described in the A2 QA note. Never edit generated JSON,
commit unless requested, or push unless explicitly asked. State clearly what
was and was not verified.
```

## 9. Current state (update on every handoff)

Date: 2026-10-13. Branch `tcf-v3`; the working tree contains uncommitted
course-source and generated-app content. The untracked `docs/v3/branding/`
folder belongs to the owner and was left untouched.

Done and in the app: Stage 0, all 14 A1 units, all 12 A2 units, all 12 B1 units,
and all 14 B2 units. The app index orders A1 → A2 → B1 → B2. It contains 732
non-dev lessons plus the hidden dev sample, and 46 stories. A2 exports 173
lessons; B1 exports 157; B2 exports 183. B1 source and its 12 chapter adapters
are in `content/tcf/book/b1_source.py` and `chapters/27_b1_unit01.py` through
`38_b1_unit12.py`. Its five vocabulary lessons per unit teach 30 focus terms
each, with 8 reusable chunks, 12 grammar targets, four-skill practice and a
four-skill entry baseline. B2 exports five vocabulary lessons per unit with 30
focus terms each and 8 reusable chunks, for a 420-term planning target. The app
still does not enforce CEFR prerequisites.

The Stories tab also contains ten new B1 and ten new B2 reading stories,
attached to Units 1–10. Their master text, sentence translations, quizzes and
story gloss are in `content/tcf/book/story_extensions.py`; `validate.py` passes
with zero errors. These additions do not include separate listening materials.
A fluent speaker should review the new French, translations and glosses before
release.

Cross-level validation: `check_book.py` reports 0 errors and 0 ledger warnings;
`validate.py` reports 0 errors and one expected warning for the hidden
`dev-sample`; `validate_b1.py` checks all 157 B1 lessons and five six-term
vocabulary sets per unit; `validate_b2.py` checks all 183 B2 lessons and five
six-term vocabulary sets per unit. The A2-only export produces 173 lessons,
1,820 steps, 516 generated checks and 12 stories; the other stage exports were
preserved. `tool/check.sh --quick` and 266 Flutter v3/mic-echo tests pass. The
complete 152-page reviewer PDF was built from the A2 chapter sources and
visually checked; see `docs/v3/A2_REVIEW_AND_DEVICE_QA.md`.

No physical iPad/iPhone course walk, production install or human French/audio
review has been done. The owner will connect the iPad for device and learner
checks. Next priorities are specialist review, device QA, course-wide review
scheduling and prerequisite gates. The B2 syllabus, grammar map and human-review checklist
are in `content/tcf/syllabus/b2.json`, `content/tcf/syllabus/grammar_b2.json`
and `content/tcf/REVIEW_NEEDED.md`.
