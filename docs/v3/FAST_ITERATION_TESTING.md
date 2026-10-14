# V3 fast iteration testing (iPhone and iPad)

> The one-stop step-by-step guide is `FAST_TESTING_PLAYBOOK.md`. This file keeps the test patterns and traps in more detail.

How this project is tested quickly, without hunting through a connected phone
for every change. Read this before you write a test or touch a device. It
explains the method, the numbers we measured, the traps we fell into, and the
exact recipes. `TESTING.md` is the reference for the on-device test scripts;
this file is the playbook for choosing and designing tests.

Everything runs from `flutter_app/` unless a path says otherwise.

## 1. The idea in one paragraph

Prove each change with the cheapest tool that can prove it. About 90 percent of
the work in this app (lesson content, step rendering, progress rules, Marie's
states, layouts on every screen size) is proven in seconds with unit and
widget tests that need no phone, no network and no money. A real device is
used only for the things a test on the Mac cannot know: a real boot, real
taps through semantics, signing, the audio route, and how it feels. Every
heavy tool is last, never first.

## 2. The ladder, with real timings

| Tier | What | Command | Measured time | Needs a phone |
|---|---|---|---|---|
| 0 | format, analyzer gate, v3 lint, content checks | `tool/check.sh --quick` | about 10 s | no |
| 1a | pure logic tests | `flutter test --no-pub test/<name>_test.dart` | under 1 s each | no |
| 1b | widget tests, one screen, fake Marie, size matrix | same | about 1 to 5 s per file | no |
| 1c | all v3 unit and widget tests together | `flutter test --no-pub test/v3_*_test.dart test/mic_echo_gate_test.dart` | about 16 s for 266 tests | no |
| 2 | one on-device integration test | `tool/e2e.sh integration_test/<name>_test.dart <device-id> <max-seconds>` | 90 to 145 s on iPhone, build included | yes |
| 3 | hot reload session for visual tuning | `tool/device.sh run` | about 25 s once, then about 1 s per change | yes |
| 4 | release build installed on a device | see section 7 | 45 s (warm) to 6 minutes (cold) | yes |

Rules that follow from the numbers:

- Start at Tier 0 and 1. Do not run Tier 2 to check something Tier 1 can prove.
- A red at a lower tier is fixed there. Never "see what the phone says".
- Tier 4 is a final smoke and a delivery step, never an iteration loop.
- One heavy job at a time. The scripts refuse a second `flutter`/`xcodebuild`.

## 3. Which test for which change

| You changed | Run first | Then |
|---|---|---|
| A lesson, word, story, unit (book chapter) | `python3 content/tcf/book/check_book.py`, `export_app.py`, `content/tcf/tools/validate.py` | `flutter test test/v3_lesson_test.dart test/v3_story_test.dart test/v3_layout_test.dart` |
| How a step looks | `test/v3_layout_test.dart` (renders every step of real lessons on 4 sizes at 1x and 2x text) | one probe screenshot on a device |
| Lesson player behaviour (back, resume, review, replay) | `test/v3_lesson_navigation_test.dart`, `test/v3_progress_test.dart` | `integration_test/v3_resume_test.dart` |
| Marie's call states, pill, mute, skip, speaker | `test/v3_marie_session_test.dart`, `test/v3_marie_ui_test.dart`, `test/v3_marie_in_lesson_test.dart` | `integration_test/v3_marie_test.dart` with the fake |
| Mic and speaker interplay (echo) | `test/mic_echo_gate_test.dart` | manual listening test (section 8) |
| A new screen | write the screen contract, widget test with the size matrix | explore probe, then one device test |
| Live Gemini behaviour (tone, length, reconnect) | cannot be tested on the Mac | manual script in section 8 |

## 4. How the tests are designed (patterns to copy)

### 4.1 Fakes at the seams, switched by `--dart-define`, debug only

Anything that costs money, needs a network or needs a human ear gets a scripted
stand-in, chosen at startup:

- `E2E_FAKE_AUDIO=true`: the story narrator and Marie use fakes. Nothing is
  billed. Guarded by `kDebugMode`, so it is compiled out of release.
- `V3MarieSession.create(...)` returns `V3FakeMarieSession` when that flag is
  on. The fake has hooks: `debugSay(text)` makes her "speak" word by word,
  `debugLearnerSays(text)`, and a static `V3MarieSession.debugLog` that records
  `start`, `start-audio`, `speak:<text>`, `mute`, `unmute`, `skip`,
  `context:step`, `context:update`, `end`. Tests assert on that log.
- `E2E_MARIE_IDLE_SECONDS=6` shortens the 90 second silence hang-up for a
  device test (ignored in release).
- `E2E_SHELL=true` skips sign-in in debug and prefixes every progress key with
  `e2e_` (`v3Key()` in `lib/v3/v3_prefs.dart`), so a test run can never read or
  erase real learning progress on the same phone.
- Widget tests inject instead of flagging: `V3LessonPlayer(marie: fake)`.

### 4.2 Make logic pure, then test it with no widgets

Whenever a rule hides inside a widget, pull it out as a static or top-level
function and test it directly. Examples that already exist:

- `V3Progress.pickNext(...)`: which lesson Resume offers (`test/v3_progress_test.dart`).
- `V3LiveMarieSession.withMemory(base, history)`: the conversation memory that
  is sent on a reconnect.
- `MicEchoGate.blocks(...)`: when the microphone must stay closed.
- `check_book.py`: the vocabulary ledger and the example-sentence rule.

### 4.3 The size matrix (this is the whole iPhone and iPad story on the Mac)

The layout of every step and of Marie's panel is checked on four sizes at two
text scales, in a loop, with no device:

```dart
const sizes = {
  'small phone': Size(320, 568),
  'phone': Size(390, 844),
  'iPad portrait': Size(810, 1080),
  'iPad landscape': Size(1080, 810),
};
for (final entry in sizes.entries) {
  for (final scale in [1.0, 2.0]) {
    testWidgets('${entry.key} at ${scale}x', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // pump the widget inside MediaQuery(textScaler: TextScaler.linear(scale))
      // assert no exception, and sensible heights (the lesson keeps room to read)
    });
  }
}
```

It caught real defects before any device saw them (overflows on the smallest
phone and at double text). Files: `test/v3_layout_test.dart` (every step of
real lessons), `test/v3_marie_ui_test.dart` (call button, panel, pill, sheet),
`test/v3_marie_in_lesson_test.dart` (a live call with a long reply inside the
lesson player on every size, must leave the lesson readable).

Wide screens: `V3Width` limits content to a readable left-aligned column, so an
iPad shows the same layout as a large phone, not stretched lines.

### 4.4 Content-driven tests: the lesson file is the oracle

Tests read the real exported lessons and answer each question from the
lesson's own key. A bad key, a missing step type, a missing example or an
unreadable file fails immediately. `test/v3_lesson_test.dart` parses every
bundled lesson; `integration_test/v3_course_walk_test.dart` plays them on a
device (`E2E_ONLY=a1-u02` filters; sample by default, `FULL_WALK=1` for all).

### 4.5 One launch per device test

Launches cost most of the time. Put related flows in one file. Boot with
`app.main()`, wait with `probe.settle` (content-based, never `pumpAndSettle`),
tap with `probe.tapLabel`, capture with `probe.capture`. Write the test against
labels the probe listed, never against something you assumed. Details and the
inspect-first protocol are in `TESTING.md`.

## 5. Traps we hit (do not repeat them)

| Trap | What happened | Rule |
|---|---|---|
| `DateTime.now()` in a widget test | the fake clock does not move it, so a 450 ms double-tap guard ignored every second tap | expose the guard as `@visibleForTesting` (`V3LessonPlayer.advanceGuard`) and set it to zero in tests |
| Real waits in widget tests | a real `Future.delayed` let Google Fonts try a network download after the test ended and fail it | do not wait on the real clock in widget tests; make the code testable instead |
| Pending timer at test end | a periodic timer in the fake Marie failed the test "Timer is still pending" | every test that leaves a call live ends it (`await marie.end()`); cancel timers in `end`/`dispose` |
| Queue shared across tests | a progress write left unfinished in one fake-time zone blocked the next test | `V3Progress.resetQueueForTest()` in `setUp` |
| SharedPreferences leaking between tests | values from one test appeared in the next | `SharedPreferences.setMockInitialValues({})` in `setUp` |
| Lazy lists | a reversed `ListView` only builds visible children, so a finder missed an off-screen line | open the sheet on the newest item and assert on that |
| `find.textContaining` matches twice | the pill and the sheet both showed the same words | scope finders with `find.descendant(of: ...)` |
| `dart format lib test integration_test` | the formatter rewrote 12 unrelated legacy files | format only the files you edited, then `git status`; revert anything unrelated |
| Screenshot-heavy course walk | held hundreds of full-size images and the iPad killed the test at about 1.85 GB | capture one screenshot per lesson, not per step |
| Reading state from a generated file | edited a generated lesson by hand | never; fix the chapter and export again |

## 6. iPhone and iPad devices

| Device | Name | Id | Notes |
|---|---|---|---|
| iPad (7th generation), iOS 18.3 | Thoufeek's iPad | `51a217780d70704c1f8e62e8000df51be95376a4` | the learner's study device, cable connected, small memory, prefer it for final installs |
| iPhone 12 Pro Max, iOS 26.6 | kodekarbon | `00008101-00124C4601EB001E` | default in `tool/lib.sh`; often on Wi-Fi, installs can drop |

Bundle id (do not change): `com.thoufeekx.frenchtutor`. The build is universal
(`UIDeviceFamily` 1 and 2). Choose a device with the second argument of
`tool/e2e.sh` or `FLUTTER_DEVICE_ID=<id> tool/e2e_all.sh`.

Facts that matter:

- A device must be in the provisioning profile or install fails. Check a built
  app: `security cms -D -i build/ios/iphoneos/Runner.app/embedded.mobileprovision | grep -c <udid>` must print 1.
- Split View and Slide Over are supported (no full-screen-only flag). Only a
  real background (`paused` or `hidden`) ends a Marie call. `inactive` (Control
  Center, tapping the other app in Split View) must not.
- Installing the same bundle id over itself keeps the data container, so the
  learner's progress survives a new build. Never uninstall to "refresh".
- A debug device test replaces the release app on that device. Reinstall the
  release build when testing is finished (section 7).

### When Flutter cannot launch the app on a device

Symptoms: `VM service never discovered`, `Timed out waiting for
CONFIGURATION_BUILD_DIR to update`, `Error starting debug session in Xcode`.
Two causes seen:

1. A previous interrupted run left the app running under a debugger (see the
   table in `TESTING.md`).
2. Xcode.app is open on the Mac. Flutter then drives Xcode and the launch
   times out. Quit Xcode and retry once.

Two failed attempts: stop and report the facts. Do not loop.

## 7. Installing a production build (release) on iPad or iPhone

Used to deliver a build for the owner to study with. Measured: 45 s to 6 min.

```
cd flutter_app
source tool/lib.sh && load_defines
rm -rf build/ios/iphoneos/Runner.app
flutter build ios --release --no-pub ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"} > /tmp/release.log 2>&1
tail -2 /tmp/release.log                                   # "Built ... Runner.app (149 MB)"
ls build/ios/iphoneos/Runner.app/Frameworks/App.framework/flutter_assets | grep -c kernel_blob   # must print 0 (release)
IPAD=51a217780d70704c1f8e62e8000df51be95376a4
security cms -D -i build/ios/iphoneos/Runner.app/embedded.mobileprovision | grep -c $IPAD       # must print 1
xcrun devicectl device install app --device $IPAD build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device $IPAD com.thoufeekx.frenchtutor
sleep 8; xcrun devicectl device info processes --device $IPAD | grep -c "Runner.app/Runner"       # 1 or more = running
```

Checks that this really is the production app: about 149 MB, no `kernel_blob`
in `flutter_assets`, signed for the device. A debug build is far larger and has
a `kernel_blob`.

## 8. What no automatic test can prove, and how to test it by hand

An agent cannot hear audio and does not call the real Gemini in tests. Give the
owner a short script. This is the current one for the lesson tutor:

1. Open a lesson. Tap the speaker on five words in a row. Is the voice the
   chosen tutor? Is each one fast and correct?
2. Switch tutor (for example Julien), reopen a lesson, tap speakers. Every
   voice should be the new tutor.
3. Tap the phone button. She says she is connected within a few seconds.
4. Ask a real question ("what does sortie mean?"). One to three natural
   sentences, no lecture. Say a word aloud: specific pronunciation feedback,
   no invented praise.
5. Ask her to repeat what is on screen. She speaks once and must not review her
   own voice. Repeat with AirPods and with the speaker.
6. Tap Continue while she talks: the old words stop, the call stays, she is
   quiet until asked. Tap Skip while she talks: she stops.
7. Stay in one lesson 10 minutes or more, moving through steps. She must stay
   on the screen you are on and must not introduce herself again.
8. Listening question: the pill must not show the sentence before you answer.
9. Go back a step, leave, return: Resume offers the furthest step.

Logs that help when something is off: `AiCostTracker` events
(`live_connect_requested`, `live_setup_complete`, `live_reconnect_scheduled`
with `reason_type`, `live_connection_ended`, `inline_live_start_failed`,
`inline_live_microphone_denied`). Ask for these before guessing a cause.

## 9. Recipes

### Add a unit's worth of content and prove it in about a minute

```
python3 content/tcf/book/check_book.py
python3 content/tcf/book/export_app.py
python3 content/tcf/tools/validate.py
flutter test --no-pub test/v3_lesson_test.dart test/v3_story_test.dart test/v3_layout_test.dart
```
Then, with a phone: `E2E_DEFINES='--dart-define=E2E_SHELL=true --dart-define=E2E_ONLY=a1-u06' tool/e2e.sh integration_test/v3_course_walk_test.dart <device-id> 900`.

For the complete A2 device walk, story pass and human iPad checklist, follow
[`A2_REVIEW_AND_DEVICE_QA.md`](A2_REVIEW_AND_DEVICE_QA.md). It splits the
173-lesson A2 walk into three prefix-filtered batches and explains how to save
each batch's evidence before the next run replaces `artifacts/e2e/`.

### Add a widget test for a new lesson step type

1. Put an example step in a real lesson JSON (via the book), so the existing
   matrix in `v3_layout_test.dart` renders it on 4 sizes at 2 text scales.
2. If the step has behaviour, copy `test/v3_lesson_navigation_test.dart`: a
   `pump(...)` helper with `V3FakeMarieSession`, `tapKey(...)`, and
   `V3LessonPlayer.advanceGuard = Duration.zero`.

### Add an on-device test

Copy `integration_test/v3_marie_test.dart` (fake, no billing, own progress keys),
register it in `tool/e2e_all.sh` with its `--dart-define`s and a timeout, run it
alone first.

## 10. Definition of done (any change)

1. `tool/check.sh` is green (format on changed files, analyzer gate, v3 lint,
   content validation, tests).
2. Anything with a layout is covered by the size matrix.
3. Behaviour that matters has a test at the lowest tier that can prove it.
4. If it touches a device flow: one on-device test passed, or the report says
   plainly that it could not run and why.
5. `git status` shows only what you meant to change.
6. Docs updated (`ROADMAP.md`, and `AGENT_RULES.md` if a rule changed).
