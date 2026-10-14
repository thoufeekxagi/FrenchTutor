# ParleSprint v3 docs: start here

ParleSprint v3 teaches French to adults from zero for TCF Canada (immigration,
citizenship, NCLC 7), on iPhone and iPad. The course is hand-authored and
deterministic. A live tutor (Gemini Live, voiced as Marie, Julien, Camille or
Mathieu) helps inside lessons. These docs let any agent or person pick the work
up from any machine and keep the same quality.

Branch: `tcf-v3`. Bundle id: `com.thoufeekx.frenchtutor` (never change).

## Read in this order

| # | Doc | Read it for |
|---|---|---|
| 1 | `HANDOFF.md` | the mission, decisions already made, how the UI is designed, ordered backlog, current state, and a copy-paste prompt for another agent |
| 2 | `AGENT_RULES.md` | the operating rules (evidence before action, stop after two failures, echo rule, progress rule) |
| 3 | `FAST_ITERATION_TESTING.md` | how to prove changes quickly on the Mac and on iPhone and iPad, test patterns, traps, device install steps |
| 4 | `LESSON_PIPELINE.md` | how units are written, checked, exported and turned into the PDF; style card; sources; the plan for Units 6 to 14 and beyond |
| 5 | `MARIE_TUTOR.md` | the in-lesson tutor: behaviour, architecture, numbers, bugs fixed, open risks |

For the complete A2 package, French/TCF reviewer handoff and three-batch iPad
course walk, read [`A2_REVIEW_AND_DEVICE_QA.md`](A2_REVIEW_AND_DEVICE_QA.md).

Reference docs: `TESTING.md` (on-device scripts and probe), `DESIGN_SYSTEM.md`
and `UI_STRUCTURE.md` (look and screens), `LESSON_FORMAT.md` and
`STORY_FORMAT.md` (file formats), `CONTENT_AUTHORING.md` (sources and gates),
`BUILD_STRUCTURE.md` (repo layout, release), `ROADMAP.md` (what is done and next),
`SCREEN_MAP.md` (generated, every screen and key), and
`A2_REVIEW_AND_DEVICE_QA.md` (A2 review status and exact on-device recipes).

## First ten minutes in the repo

```
git checkout tcf-v3 && git pull
git log --oneline -10                          # what changed last
cd flutter_app
tool/check.sh --quick                          # format, analyzer gate, lint, content (about 10 s)
flutter test --no-pub test/v3_progress_test.dart test/v3_lesson_navigation_test.dart   # a feel for the tests
python3 ../content/tcf/book/check_book.py     # the course checks
```

## The four jobs and the commands that matter

| Job | Commands |
|---|---|
| Write a unit | edit `content/tcf/book/chapters/NN_*.py`, then `check_book.py`, the stage-scoped `export_app.py`, and `content/tcf/tools/validate.py`. Build the matching reference PDF after the stage is complete; A2 uses `build_a2_review.py` (see `LESSON_PIPELINE.md`) |
| Change the app | `tool/check.sh --quick`, then `flutter test --no-pub test/<file>`, then one device test if behaviour needs it |
| Test on a device | `E2E_DEFINES='--dart-define=E2E_SHELL=true' tool/e2e.sh integration_test/<name>_test.dart <device-id> 600` |
| Deliver a build to the iPad | release build and `xcrun devicectl device install app` (exact steps in `FAST_ITERATION_TESTING.md` section 7) |

## Who takes over what

- **Content and logic, no phone needed**: writing units, checkers, exporter,
  PDF, Flutter code with Mac tests, docs. Any agent.
- **Device work**: on-device tests, release builds, installs on the iPad and
  iPhone, signing. An agent with access to the connected devices.
- **A human**: listening to audio, judging pronunciation and tone, the French
  review in `content/tcf/REVIEW_NEEDED.md`, App Store decisions.

Before you start: read the "Current state" block in `HANDOFF.md`. Before you
stop: commit, update that block and `ROADMAP.md`, say what you could not verify.
One agent per area at a time.

## Non-negotiables (short form)

1. Hand-authored course, cumulative vocabulary, every word has an example, Canadian context.
2. The book is the source; never edit generated files in `flutter_app/assets/content/tcf/`.
3. Cheapest test first; fakes for anything that costs money; size matrix for layouts.
4. The tutor never hears herself. Speakers ask the tutor. Progress only moves forward.
5. One design: Inter, V3 primitives, tokens, no gamification, no em dashes in UI copy.
6. Two failed attempts: stop and report. Never push unless asked. Never commit secrets.
