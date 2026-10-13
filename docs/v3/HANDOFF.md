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

Gemini Live (the tutor, voiced as Marie, Julien, Camille or Mathieu) makes
learning faster: pronunciation, explanations, speaking practice. It is never
the source of the curriculum. The curriculum is authored files, validated.

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
  onboarding/                     launch, welcome, level, tutor voice, rhythm, plan, account gate
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
exact steps): launch screen, welcome, level choice, tutor voice (Marie, Julien,
Camille, Mathieu), daily rhythm, a plan screen that states real facts (level,
target, time per day), then the account gate. No fake progress, no scores. Device test:
`integration_test/v3_onboarding_test.dart`.

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
| 1 | **A1 Units 6 to 14** (book chapters, then export) | each unit meets "Definition of done" in `LESSON_PIPELINE.md`; PDF rebuilt; all new lessons play in the course walk |
| 2 | **Inline Marie in the story reader** | `V3MarieSession` in the reader, narration and call share one socket, tests with the fake |
| 3 | **Review (spaced repetition)** over words learned, missed and saved | Learn shows a real review card; nothing invented; unit tests for the scheduler |
| 4 | **TCF mock engine** | real timers, one-play audio, 39-question sets, estimate labelled as an estimate |
| 5 | **Writing and speaking feedback** | one concise correction, one better version, one reason; no invented scores |
| 6 | **A1 mini mocks** after Units 5, 10, 14 | 10 listening and 10 reading in real format |
| 7 | **A2, B1, B2** | same method; targets in `ROADMAP.md` |
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
`tool/check.sh --quick`. Before stopping, commit, update the block and
`ROADMAP.md`, and say what you could not verify.

## 8. Copy-paste prompt for another agent

```
You are continuing ParleSprint (TCF Canada French app) in this repo, branch tcf-v3.
Read docs/v3/README.md, then docs/v3/HANDOFF.md, docs/v3/AGENT_RULES.md,
docs/v3/FAST_ITERATION_TESTING.md and docs/v3/LESSON_PIPELINE.md before changing anything.
Your task: <say which backlog item, for example "write A1 Unit 6, Days, time and appointments">.
Rules: hand-author content in content/tcf/book/chapters/NN_*.py (never edit generated
files in flutter_app/assets/content/tcf/), run check_book.py, export_app.py, validate.py,
the Flutter content tests, rebuild the PDF, commit the unit alone. Use the cheapest test
first. Report plainly what you did not verify. Do not push unless asked.
```

## 9. Current state (update on every handoff)

Date: 2026-10-13. Branch `tcf-v3`, pushed to `origin/tcf-v3`.

Done and in the app: Stage 0 (13 lessons) and A1 Units 1 to 5 (87 lessons in
total, 1,053 steps, 5 stories), all 290 word steps with example sentences;
premium story reader; inline Marie with speaker taps, response pill, Mute,
Skip, echo gate; real progress, Previous, review and replay; iPhone and iPad
build; production build installed on the iPad.

Verified: 138 unit and widget tests pass (progress, navigation, Marie, layouts
on four sizes at two text scales, lessons, stories). The analyzer gate is at
its baseline of 34 known items. The v3 lint is clean.

Not verified on a device: the newest on-device tests (resume with Previous,
Marie fake test) did not launch because Xcode was open on the Mac; real
Gemini behaviour (tone, echo with AirPods, reconnect over a long lesson) needs
the manual script in `FAST_ITERATION_TESTING.md` section 8.

Next: backlog item 1 (Units 6 to 14). Open owner questions: none.

Known issues and risks: see `MARIE_TUTOR.md` section 8, and
`content/tcf/REVIEW_NEEDED.md` (a fluent speaker must confirm sound guides and
Canadian usage notes). The untracked folder `docs/v3/branding/` is the owner's
and is not part of this work.
