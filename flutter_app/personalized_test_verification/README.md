# Personalized content verification harness

Simulates a learner going through day 1→30 at each CEFR level (A1/A2/B1/B2)
using the app's real content-generation code (`ContentService`, `SRSService`,
`LessonAgentService`, `LearningStore` — not a reimplementation), and produces
one PDF report per level so pacing, CEFR calibration, and content variety can
be reviewed without waiting 30 real days or being fluent enough yourself to
judge a B2 lesson.

Not part of the shipped app — same category as `tool/generate_mission_bank.dart`.

## Why `flutter test`, not `dart run`

`ContentService` loads `assets/content/*.json` through Flutter's `rootBundle`,
and `SRSService`/`LessonAgentService` read settings via `SharedPreferences` —
both need a Flutter engine, which a plain `dart run` script doesn't have. The
simulate step runs under `flutter test` instead, which provides a real
`rootBundle` and a mockable `SharedPreferences` — that's the only reason it's
shaped like a test file; it isn't actually testing anything, it's a
simulation driver. `verify_journey.dart` and `generate_report.dart` need
neither and run as plain `dart run` scripts.

## Running

One level, short smoke run:

```bash
DAYS=3 ./personalized_test_verification/run_all.sh a1
```

One level, full 30 days:

```bash
./personalized_test_verification/run_all.sh a1
```

All four levels, full 30 days each (this hits real Gemini — see cost note below):

```bash
./personalized_test_verification/run_all.sh
```

Reports land in `personalized_test_verification/reports/<LEVEL>_report.pdf`.
Raw data lands in `personalized_test_verification/output/` (`<level>_journey.json`,
`<level>_verdicts.json`) if you want to inspect it directly.

Requires `GEMINI_API_KEY` in `secrets.local.properties` (same file
`run_with_keys.sh` already reads).

## Cost / time

Each simulated day makes roughly 9 Gemini Flash-Lite calls (vocab plan,
grammar plan + practice cards, story/listening + quiz, writing task +
grading, a synthetic-learner submission, roleplay). A full run is
30 days × 4 levels × ~9 calls ≈ **1,000+ calls total** — small individually
(Flash-Lite is the cheapest tier, the same model the app ships with) but
non-zero, and it'll take a while. Run a `DAYS=3` smoke test on one level
first to confirm everything works before committing to a full batch.

## What's simulated vs. not

- **Real**: vocab session planning/pacing, SRS scheduling math (interval/ease
  growth), grammar topic selection + practice cards, story/listening
  generation, writing task generation + AI grading, standalone roleplay
  generation — all through the actual production service calls.
- **Synthetic learner**: there's no real person answering, so
  `harness/synthetic_learner.dart` picks SRS grades from a tunable weighted
  distribution (mostly "good", some slip-ups) and asks Gemini to role-play a
  plausible imperfect written submission at the target level. Change the
  weights there to model a stronger/weaker learner.
- **Starting knowledge**: A1 starts from zero. A2/B1/B2 pre-seed 1/2/3 of the
  bundled vocab phases as already-known before day 1 — a B2 run isn't a
  beginner learning from scratch, it's meant to look like someone who's
  already at that level, since that's the population whose content quality
  you're actually trying to check.
- **Not simulated**: voice/speech (TTS/STT, live conversation sessions) — the
  content-generation methods this harness touches are all text-only;
  `LessonAgentService`'s speech methods are out of scope.
- **Clock**: `SRSService`/`LearningStore` stamp real `DateTime.now()` with no
  injection seam. `harness/clock_shift.dart` corrects the written dates after
  each simulated day completes (real interval/ease math still runs
  untouched) rather than patching production source — see the comments in
  that file for exactly what it does and its one known edge case (a run
  spanning real local midnight).

## Resuming / re-running

`simulate_journey_test.dart` writes `output/<level>_journey.json` after every
simulated day, so a crash partway through doesn't lose earlier days — but a
rerun of the same level starts over from day 1 rather than resuming mid-run
(re-hydrating the in-memory SRS/grammar state exactly is more complexity than
this is worth for a test tool). If a level's journey file already has
`daysRequested` or more days recorded, rerunning it is a no-op — delete the
file first to force a fresh run.
