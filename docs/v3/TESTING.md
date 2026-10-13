# V3 testing and fast iteration rules

> Start with `FAST_ITERATION_TESTING.md` (how tests are chosen and designed, iPhone and iPad). This file is the reference for the on-device scripts and probe.

Goal: no assumptions, no trial and error. Every claim about the app (a screen
exists, a button is called X, a tap does Y) must come from a tool result in the
current session: the probe, a screenshot, the screen map, or the source.

All commands run from `flutter_app/`. Measured on this Mac with kodekarbon
(iPhone 12 Pro Max, iOS 26.6).

## The ladder (cheapest first, stop at the first red)

| Tier | Command | Typical time | Catches |
|---|---|---|---|
| 0 | `tool/check.sh --quick` | ~10s | format, analyzer errors/warnings, v3 key lint, content validation |
| 1 | `tool/check.sh [test files]` | seconds to ~1 min | logic, widget structure, golden layout |
| 2 | `tool/e2e.sh integration_test/<name>_test.dart` | 90s cold, ~95s warm | real device boot, taps, screenshots, semantics |
| 3 | `tool/device.sh run` (hot reload) | ~25s build, then ~1s per change | visual tuning with a live session |
| 4 | Release build on the phone | minutes | final smoke only, never for iteration |

Measured: the first device build is ~72s, later builds 23 to 33s. A whole e2e
run (build, install, launch, test, collect) is 90 to 145s. Do not run Tier 2
to check something Tier 0 or 1 can prove.

Xcode's MCP `DeviceInteraction*` tools only support the iOS 27+ Simulator, not
a physical iPhone, and the app currently cannot build for the simulator
because `google_mlkit_*` has no arm64 simulator slice. Do not try them against
the phone. Removing Photo tutor and ML Kit in v3 unlocks simulator
interaction (see BUILD_STRUCTURE.md).

## Device tests that exist today

| Test | Run | What it proves |
|---|---|---|
| `integration_test/smoke_test.dart` | `tool/e2e.sh integration_test/smoke_test.dart` | app boots, first screen is describable |
| `integration_test/explore_test.dart` | `tool/e2e.sh ...` (add `E2E_DEFINES='--dart-define=E2E_DARK=true'` for dark) | discovery walk, saves every screen and its tappables |
| `integration_test/v3_onboarding_test.dart` | `E2E_DEFINES='--dart-define=SKIP_NOTIFICATION_PROMPT=true' tool/e2e.sh ...` | launch, welcome, level, Marie, rhythm, plan, then the account gate. Asserts facts on the plan screen |
| `integration_test/v3_lesson_test.dart` | `E2E_DEFINES='--dart-define=E2E_SHELL=true' tool/e2e.sh ...` | plays the dev sample lesson from Learn to completion: every step type, wrong then right answer, score, missed list, completion saved, hero moves on. Never taps a speaker (that would call Gemini Live and cost money) |
| `integration_test/v3_course_walk_test.dart` | `E2E_DEFINES='--dart-define=E2E_SHELL=true' tool/e2e.sh integration_test/v3_course_walk_test.dart <device-id> 900` | plays EVERY authored lesson on the phone, answering each question from the lesson file's own key. Fails if any lesson does not load, any step cannot render, any key is not accepted, or a lesson does not finish with a perfect score and get recorded. Run it after adding or editing any lesson (about 4 minutes for 4 lessons) |
| `integration_test/v3_story_test.dart` | `E2E_DEFINES='--dart-define=E2E_SHELL=true --dart-define=E2E_FAKE_AUDIO=true' tool/e2e.sh integration_test/v3_story_test.dart <device-id> 900` | Stories list and level chips, reader, the small word card, hear-words on and off, translation toggle, playback and speed controls, Words tab and saving, quiz and completion for every story, Dark mode. `E2E_FAKE_AUDIO` swaps live Marie for a free fake, so nothing is billed. The real voice is tested by hand |
| `integration_test/v3_shell_test.dart` | `E2E_DEFINES='--dart-define=E2E_SHELL=true' tool/e2e.sh ...` | four tabs, exam countdown, Path units, TCF format numbers, dark toggle persists |

**Run everything:** `tool/e2e_all.sh` runs every v3 device test one at a time with the right flags and prints a pass/fail table (about 15 minutes). `tool/e2e_all.sh story` runs only matching tests. Screenshots are kept in `artifacts/e2e_all/<test>/`.

**Course walk filter.** `E2E_ONLY=s0-01,a1-u02` (a `--dart-define`) limits `v3_course_walk_test.dart` to lessons whose id starts with one of the prefixes. `tool/e2e_all.sh` walks a representative sample (about 9 minutes). `FULL_WALK=1 tool/e2e_all.sh walk` plays every lesson (about an hour, 1 000+ steps).

**Test progress is separate from real progress.** In debug builds started with `E2E_SHELL`, every progress key is stored with an `e2e_` prefix (`lib/v3/v3_prefs.dart`, `v3Key()`), so a test run can never read or erase what you learned on the same phone.

`tool/e2e.sh` stops any leftover copy of our own app on the phone before each run (matched by bundle id, never other apps). A copy still running under a debugger makes Flutter's launch fail.

`E2E_SHELL` is a debug-only switch in `lib/app.dart` (guarded by `kDebugMode`, so
it is compiled out of release builds). It skips sign-in so the shell can be
tested without a real account. `SKIP_NOTIFICATION_PROMPT` skips the iOS
permission alert, which the driver cannot tap.

## Baselines (what "green" means today)

The restore-point snapshot already had failures. They are recorded, so the gate
fails only on regressions:

- `tool/known_test_failures.txt`: 11 stale tests (copy and token expectations
  that drifted from the product). Verified by running them on the untouched
  tag `pre-v3-2026-10-12`: same 11 fail.
- `tool/known_analyzer_issues.txt`: 34 errors/warnings. One is a real break:
  `lib/services/audio_streaming_service_web.dart` does not implement
  `preparePlayback` / `isAwaitingTutorResponse` added to the iOS service, so a
  web build is broken (iOS is unaffected). Fix it only if web is revived.

When you fix a baseline item, delete its line (analyzer: `python3
tool/analyze_gate.py --update`, then review the diff). Never add a line to hide
a failure you caused. The gate was proven both ways: an injected error fails it,
removal passes it.

## The inspect-first protocol (mandatory)

1. Need to test or change a screen? First `python3 tool/screen_map.py --find <name>`
   and read the source file. Know the widget, its keys and its route.
2. Never write a tap or an expectation against something you have not seen.
   Run `tool/e2e.sh integration_test/explore_test.dart` (or a one-screen probe)
   and read `artifacts/e2e/probe.json` and `artifacts/e2e/shots/*.png`.
3. Write the real test against labels and keys that the probe listed.
4. If the test fails, read `artifacts/e2e/run.log`, `probe.json` and the
   `timeout_*.png` screenshot before changing anything. The failure message
   already includes what was visible.
5. Two failed attempts at the same problem: stop, state what the facts show,
   ask for direction. No third blind retry.

## Writing on-device tests

- One file = one app launch. Group related flows in a single file, and use
  `group`/multiple `testWidgets` only when state can be shared. Launches cost
  most of the time.
- Always `tester.ensureSemantics()` first and dispose at the end.
- Boot with `app.main()` then `probe.settle(tester)`. Never `pumpAndSettle`
  (live animations and network keep this app from settling and the test hangs).
  `settle` waits until the visible text stops changing, not merely until frames
  stop, because the app is frame-idle during async startup.
- Tap with `probe.tapLabel(tester, 'Label')`. It uses the exact rect from the
  probe, divided by the device pixel ratio (semantics rects are physical
  pixels, about 3x the logical size). For `Title\nSubtitle` rows use
  `startsWith: true`.
- Wait with `probe.waitFor(tester, finder)`. Its timeout failure includes the
  screen description and a screenshot.
- Capture with `probe.capture(tester, '03_today')`. The probe merges into
  `reportData`. Never assign `binding.reportData = ...` (it deletes screenshots).
- Payments are bypassed with the debug-only key
  `SharedPreferences.setBool('dev_force_pro_unlock', true)` before `app.main()`.
  Never run a purchase flow in a test. `explore_test.dart` refuses to tap
  anything containing subscribe, purchase, buy, delete, sign out, log out,
  restore.
- Assert on facts: a label exists, a screen text appears, a count changed.
  Do not assert on pixel colors or exact animation timing.

## Keys, labels and semantics (so tests never guess)

- Every interactive widget in `lib/v3/**` has a stable key
  `ValueKey('<screen>.<element>')`, for example `today.nextLesson`,
  `lesson.askMarie`, `paywall.annualPlan`. `tool/check.sh` fails the build on
  an untagged `onTap`/`onPressed` there.
- Every tappable also has a human Semantics label. The label is the test
  contract and the VoiceOver label. It must be on the button itself, never on
  a wrapper around the screen. Measured defect in the current app: the
  onboarding "Continue" semantics node spans the whole body (rect height 2439
  physical px), so tapping its centre hits the wrong row. The probe flags this
  as `oversized`. Fix it at the source when touching that screen, and never
  copy the pattern.
- Do not put the same label on two tappables on one screen.

## Known failure modes and the response

| Symptom | Cause | Response |
|---|---|---|
| `Dart VM Service was not discovered` and white screen | app did not start on device (signing, locked phone, stale install) | `tool/e2e.sh` kills it after 150s. Unlock phone, `tool/device.sh relaunch`, retry once only |
| `BLOCKED: another heavy job` | another flutter/xcodebuild running | stop it, never run in parallel |
| `DEVICE NOT CONNECTED` | locked, unplugged, or untrusted | unlock, replug, `tool/device.sh list` |
| Screenshot missing but test passes | `reportData` was replaced | use `probe.capture` only |
| Tap changes the wrong thing | tapped an oversized semantics node | probe marks it `oversized`, `tapLabel` falls back to the text |
| Test passes but captured "Restoring your progress..." | settled before async startup ended | use `probe.settle` (content-based) |
| Log says `You may be prompted to give access to control Xcode`, then VM service not found, and Xcode.app opens by itself | Flutter's LLDB launch failed, usually because a previous (interrupted) run left ParleSprint running under a debugger on the phone, so it fell back to driving Xcode | `xcrun devicectl device info apps --device <id> --bundle-id com.thoufeekx.frenchtutor --verbose` shows the app's bundle path. `xcrun devicectl device info processes --device <id> \| grep Runner` lists pids. Match the path, then `xcrun devicectl device process terminate --device <id> --pid <pid> --kill` (a plain terminate did not stop it). Never kill the other Runner (a different app). SIGTERM the Xcode.app and `lldb-rpc-server` that your own failed run launched, then retry once |
| `Timed out waiting for CONFIGURATION_BUILD_DIR to update` / `Error starting debug session in Xcode`, then `VM service never discovered` | Xcode.app is open on the Mac and Flutter's launch drives Xcode | quit Xcode, retry once. Two failures: stop and report |
| Orphaned `flutter drive` or `lldb` after an aborted run | parent died | `ps -axo pid,ppid,etime,command | grep -E "dartvm|lldb"`, SIGTERM the orphans |

## Unit and widget tests

- Test pure logic (planners, validators, scoring, SRS) with `flutter test`.
  They run in seconds and need no device.
- Widget tests pump one screen with provider overrides. Use the in-memory
  database helpers in `test/` as the pattern. Add a golden only for stable,
  finished layouts.
- Content is tested by `content/tcf/tools/validate.py`, not by hand.

## Definition of done for any change

1. `tool/check.sh` passes.
2. For UI: the probe lists the new labels, a screenshot exists and was looked
   at, at the default and a large text scale.
3. For behavior: one on-device test drives it end to end.
4. `git status` is understood. Nothing unrelated was reformatted. If a
   formatter or generator touched an unrelated file, revert that file.

## Progress and navigation

`test/v3_progress_test.dart` (frontier only moves forward, finished lessons get none, `pickNext` order) and `test/v3_lesson_navigation_test.dart` (Previous, Go to step N, review does not rewrite progress, replay changes nothing, answered questions persist, skip when reviewing). `integration_test/v3_resume_test.dart` also goes back a step before leaving and checks Resume still offers the furthest step.

