# Fast testing playbook (one-stop guide for any AI agent or IDE)

How to plan a change, code it, and prove it works quickly and safely, on the Mac
and on a connected iPhone or iPad. Everything here was run on this project. The
numbers are measured, not guessed. Run commands from `flutter_app/` unless a
path says otherwise.

If you read only one thing: **cheapest proof first, one heavy job at a time,
look at the screenshot, and never rerun a test that already passed.**

## 0. The 60-second summary

1. Plan: write the screen contract or the rule in one paragraph (what must be true).
2. Prove on the Mac first: `tool/check.sh --quick` (about 10 s), then the one
   focused `flutter test` file.
3. If the change needs an app launch, run one Debug simulator test with
   `tool/simulator.sh test integration_test/smoke_test.dart` when a physical
   phone is unavailable. The script enforces one booted simulator. Use the
   wired iPhone only when the behavior requires physical hardware.
4. Look at the screenshots. A green test with a wrong picture is a failed test.
5. Commit in small pieces. Push only when asked.

## 1. Before you start (a 2-minute checklist)

Run these, read the output, then decide. Do not assume.

```
git status -sb && git log --oneline -5          # what is already changed, who touched it last
uptime                                           # load average; see section 4
ps -axo pid,etime,command | grep -E "xcodebuild|flutter_tools|flutter_tester|dartvm|devicectl|parlesprint" | grep -v grep
xcrun devicectl list devices                     # is the phone connected (state "connected")
python3 tool/screen_map.py --find "<screen or label>"   # where is the screen you will change
```

Rules that come from this checklist:
- Another agent or the owner may be editing the same files. `git status` first;
  never reformat or revert files you did not change.
- If a process from an earlier run is still alive, it is stale. Section 5 says how to clear it.
- Devices:
  - iPhone 12 Pro Max `00008101-00124C4601EB001E` (default in `tool/lib.sh`)
  - iPad (7th generation) `51a217780d70704c1f8e62e8000df51be95376a4` (the owner's study device)
  - A cable is much faster and more reliable than Wi-Fi. Builds and installs drop on Wi-Fi.
  - Prefer the iPhone for tests. The iPad has the learner's app: install over it only on purpose.
- Simulator development uses the dedicated iPhone 17 Pro (ID and recovery
  commands are in `BUILD_STRUCTURE.md`); keep only one simulator booted and use
  Debug builds. On runtime instability or lag, the owner authorized erasing
  that simulator with `tool/simulator.sh reset`. Reset does not fix compile or
  test assertion failures.

## 2. The ladder: which test for which change

| Tier | Command | Measured time | Use it for |
|---|---|---|---|
| 0 | `tool/check.sh --quick` | about 10 s | format of changed files, analyzer (new issues only), v3 lint, content validation. Before every commit |
| 1 | `flutter test --no-pub test/<file>_test.dart` | 1 to 5 s per file | logic, copy, rules, and widgets with a fake |
| 1+ | `tool/check.sh` | about 40 to 100 s (684 tests) | the whole Mac suite; fails only on NEW failures vs the baseline files |
| 2 | `tool/e2e.sh integration_test/<name>_test.dart <device-id> <max-seconds>` | 110 to 290 s wired | one real-device flow, with screenshots |
| 3 | release build and install | 343 s (cold) | handing a build to the owner. Never an iteration loop |

For a simulator build/launch proof, use `tool/simulator.sh test` (Debug only,
one booted simulator, unique artifacts under `artifacts/simulator/`). Use
`tool/simulator.sh run` for interactive development. Do not use Profile or
Release for simulator iteration.

Choose by the question you are asking:
- "Is my logic right?" Tier 1, a pure function, no widgets. (Example: the review queue and the pledge copy are pure and have 12 and 11 tests that run in under a second.)
- "Does it lay out on every screen?" Tier 1 widget test with the size matrix (small phone 320x568, phone 390x844, iPad 810x1080, iPad landscape 1080x810, text 1x and 2x).
- "Does the real app, with real taps, do it?" Tier 2, once.
- "Can I hand it to the owner?" Tier 3.

Measured device test times on the wired iPhone (build included): home 129 s,
onboarding 109 s, lesson 187 s, resume 287 s, Marie with a fake 154 s. The first
build after a long gap is slower (228 s). Do not run a Tier 2 test to check
something a Tier 1 test can prove.

## 3. Plan, code, run: the loop

1. **Write the claim down.** One line: "Skipping reminders finishes onboarding." "The home card says Continue path." If you cannot state it, you cannot test it.
2. **Write the failing test first** (when there is a bug). Run it and read the failure. A test you have never seen fail proves nothing. Example from this project: the profile-saving crash was reproduced by a 10-line store test before the one-line fix.
3. **Make the smallest change** that reuses an existing primitive (`V3Button`, `V3Pressable`, `DesignTokens`, never a new colour or font).
4. **Tier 0**, then the one focused Tier 1 file.
5. **One Tier 2 run** only if the change needs a phone.
6. **Look at the screenshot** in `artifacts/e2e/shots/`. Compare it to the approved design, not to your memory.
7. **Commit** the piece, with a message that says why.

### Classify every failure before you touch anything

| Evidence | It is | Action |
|---|---|---|
| The screenshot looks right but a label or text was not found | the test is stale | fix the test |
| The screenshot is wrong, a crash, or a log shows an exception in app code | the app is wrong | write a regression test, fix the app |
| It passes alone and fails only in the full run, with a timing limit in the test | flaky under load | note it, do not chase it |

Examples seen here: the old onboarding test waited for text that no longer exists (test wrong); skipping reminders threw `NOT NULL constraint failed: profiles.preferred_days` (app wrong, and a new user would have been stuck); `unit_two_authored_content_test.dart` asserts `lessThan(500)` ms and fails only when the Mac is busy (flaky).

**There is no fixed retry cap.** Read the latest evidence and change the
diagnosis or test method on each run. Continue until the requested result works
or progress requires owner-only access.

## 4. The machine: one heavy job at a time

The laptop has 16 GB. Heavy jobs are `flutter test` on many files, `flutter build`, `xcodebuild`, `flutter drive`.

- One at a time. Check with the `ps` line in section 1 before starting.
- `tool/e2e.sh` refuses to start when the load average is above 12 and prints `BLOCKED: load average is N (limit 12)`. The result file `artifacts/e2e/result.txt` is then left over from the previous run, so **do not read a stale `result.txt` as this run's result**. Read the log of the run you just started.
- Load spikes come from macOS Spotlight indexing (`Metadata`), a compile, or other apps. A release compile makes load rise to about 20 for a few minutes. That is normal.
- If load is high, wait. Do not start a second build to "see if it is faster".

A small wrapper that waits for the Mac to calm down (used here to run several device tests in a row):

```bash
#!/usr/bin/env bash
cd /path/to/FrenchTutor/flutter_app || exit 2
DEV=00008101-00124C4601EB001E
OUT=/tmp/my_run_out; rm -rf $OUT; mkdir -p $OUT      # a folder you own
TESTS=(
 "v3_home_test.dart|--dart-define=E2E_SHELL=true|600"
 "v3_onboarding_test.dart|--dart-define=SKIP_NOTIFICATION_PROMPT=true|600"
)
for entry in "${TESTS[@]}"; do
  IFS='|' read -r file defs max <<<"$entry"; name="${file%_test.dart}"
  for i in $(seq 1 40); do
    L=$(uptime | sed 's/.*averages: //' | awk '{print $1}' | tr -d ',')
    awk "BEGIN{exit !($L < 11.5)}" && break; sleep 10
  done
  echo "$(date +%H:%M:%S) START $file" >> $OUT/progress.txt
  E2E_DEFINES="$defs" tool/e2e.sh "integration_test/$file" "$DEV" "$max" > "$OUT/$name.log" 2>&1
  line=$(grep -E "^== (PASS|FAIL|TIMEOUT)|BLOCKED" "$OUT/$name.log" | head -1); [[ -z "$line" ]] && line="== NO RESULT"
  mkdir -p "$OUT/$name"; cp -R artifacts/e2e/shots/. "$OUT/$name/" 2>/dev/null; cp artifacts/e2e/run.log "$OUT/$name/run.log" 2>/dev/null
  echo "$(date +%H:%M:%S) DONE  $file  $line" >> $OUT/progress.txt
done
echo ALLDONE >> $OUT/progress.txt
```

Start it with `nohup script.sh > /tmp/x.txt 2>&1 &` and read `progress.txt`.
`artifacts/e2e/` is wiped by the next run, so the wrapper copies each run's shots.

### Running long jobs from an agent tool

Most agent shells time out around 4 minutes and cancel the call if the user interrupts. So:
- Start long jobs in the background (`nohup ... &` or `(cmd > log 2>&1 &)`), then poll with `sleep 200; tail log`.
- Never poll in a tight loop. One check every 2 to 4 minutes.
- macOS has no `timeout` command. Use a background run plus a polling loop with a limit.

## 5. Stale processes and locks: how to clean up safely

List first (section 1). Kill only what **you** started.

- A leftover `devicectl device process launch` from an interrupted run: `kill <pid>`.
- Leftover test runners: `pkill -f "integration_test/<name>"`, `pkill -f "tool/e2e.sh"`, `pkill -f "flutter_tester.*<name>"`.
- Your own wrapper script: `pkill -f <your_script_name>`.
- Never kill Xcode, the Devin or editor processes, or another person's job.
- `tool/e2e.sh` already stops a leftover copy of our own app on the phone (by bundle id) before each run. A copy left running under a debugger makes Flutter's launch fail.

`.git/index.lock`: if git says it cannot create it, check there is no git process
(`ps ... | grep "git "`) and look at the file's age (`ls -la .git/index.lock`).
A zero-byte lock hours old with no git process is stale. Remove only that file.
Happened twice here (probably an editor extension that crashes mid-operation).
If a git process is running, wait.

## 6. Device testing in depth

### Before the run
- `xcrun devicectl list devices` shows the phone as `connected`. A cable is best.
- The phone must be unlocked and trusted. A locked phone refuses a remote launch
  (`FBSOpenApplicationServiceErrorDomain error 1`, seen on the iPad).
- Xcode.app must not be open, or Flutter's launch can time out
  (`Timed out waiting for CONFIGURATION_BUILD_DIR`, `VM service never discovered`).
- The device must be in the signing profile:
  `security cms -D -i build/ios/iphoneos/Runner.app/embedded.mobileprovision | grep -c <udid>` prints 1.

### Safe test data
- Debug test builds use `--dart-define=E2E_SHELL=true`. It skips sign-in and
  prefixes every progress key with `e2e_`, so a test never reads or erases real
  learner progress. Never uninstall the app to "reset"; install over it.
- `--dart-define=SKIP_NOTIFICATION_PROMPT=true` skips the iOS permission alert.
- `--dart-define=E2E_FAKE_AUDIO=true` swaps live Marie and story narration for a free fake. Nothing is billed.
- Never tap a speaker or open a live Marie call in a test. That costs money.

### Filters that make a run short
- `E2E_ONLY=a2-u01-words-1,b1-u01-diagnostic` limits the course walk to lessons whose id starts with one of the prefixes.
- `E2E_STORY_ONLY=<id prefix>` limits the story test.
- Pick samples that cover every stage (Stage 0, A1, A2, B1, B2) instead of all 733 lessons. The full walk takes about an hour.

### Writing a device test
Copy `integration_test/v3_home_test.dart` (the shortest one). The pattern:
`app.main()`, `probe.waitForLabel`, `probe.settle` (never `pumpAndSettle`),
`probe.tapLabel`, `probe.capture`, then assert on `probe.describe(tester)`
(`texts`, `tappable`). Write the test against labels the probe printed, never
against something you assumed. Details: `TESTING.md`.

### Reading a result
The log of the run (`artifacts/e2e/run.log`, or your wrapper's copy) ends with
`== PASS in Ns` or `== FAIL`. On failure, the first `EXCEPTION CAUGHT` block
names the missing label and lists the visible tappables. A `timeout_<ts>.png` is
saved next to the shots. **Open the picture.**

## 7. Mac test traps (each one cost time here)

| Trap | Symptom | Fix |
|---|---|---|
| Real-clock waits in a widget test | `google_fonts was unable to load font Inter-Bold` fails the test, or the test hangs at 0% CPU | avoid real waits; prefer a Tier 2 device test for screens that load many assets |
| `pumpAndSettle` | hangs on periodic timers | `pump(Duration)` in steps |
| A page slide or fade | the next screen's text is not there yet | pump 100 ms, then 900 ms (the transition starts on the next frame) |
| `DateTime.now()` in a guard | a 450 ms double-tap guard ignores the second tap | expose the guard as `@visibleForTesting` and set it to zero in the test |
| Pending timer at test end | "A Timer is still pending" | end the call and cancel timers in `dispose` |
| `SharedPreferences` leaks between tests | values from the previous test | `SharedPreferences.setMockInitialValues({})` in `setUp` |
| Queue shared between tests | a write blocks the next test | `V3Progress.resetQueueForTest()` in `setUp` |
| `dart format` on directories | unrelated files change | format only the files you edited, then `git status` |
| A test with a wall-clock assertion | passes alone, fails in the full run | do not chase it; it is the machine load |

If a Mac test is hung (running minutes at 0% CPU), kill your own `flutter_tester`
for that file and do not retry the same thing. Move the check to Tier 2.

## 8. Content and generated files

- Chapter sources in `content/tcf/book/` are the master. `flutter_app/assets/content/tcf/` is generated. Never hand-edit generated files.
- **A full `python3 content/tcf/book/export_app.py` deletes every lesson file first, then rewrites them.** If it stops partway, the lesson folder is empty while `course.json` still lists every lesson (the validator then reports hundreds of "file does not exist" errors). Before running it:
  1. back up (a `tar` into a folder under `/tmp` that you own);
  2. or test it in a throwaway copy of `content/tcf` and `flutter_app/assets/content` under `/tmp` and compare.
- Use `--a2-only`, `--b1-only`, `--b2-only` to replace one stage without touching the rest.
- After any export: `python3 content/tcf/book/check_book.py`, `python3 content/tcf/tools/validate.py`, `validate_b1.py`, `validate_b2.py`. Expect 0 errors (one warning for the hidden `dev-sample` is normal).
- Regenerating Stage 0 and A1 must give byte-identical files to git. Verify with `git status`: no lesson file should show as modified.

## 9. Edge-case checklist (use it on every screen)

- First-time learner with no progress; with progress; with everything finished.
- Every optional step **skipped** (this found a real crash: a skipped reminder wrote an empty value into a required column).
- Back, forward, and double-tap.
- Long text: a long reading passage pushes the answers off-screen. A test must scroll to the option (`tester.drag` on the `Scrollable`), as a learner would.
- Small phone (320 wide) and 2x text. Rows and tab bars overflow first. Use `Expanded` and `FittedBox` for short labels.
- iPad portrait, landscape, and a narrow Split View.
- Light and dark appearance.
- No network, microphone denied, app sent to the background mid-call.
- Selected controls use the action blue with white text, never black.
- No em dashes in user-facing text.
- Never promise a result ("get ready for the exam", not "you will pass").

## 10. Builds for the owner

| Build | How | Behaviour |
|---|---|---|
| Debug (`flutter run`, `flutter drive`) | tests only | **stops working when unplugged**; iOS 14 and later refuses to relaunch a debug build from the home screen |
| Release | `flutter build ios --release` | works from the home screen any time. 343 s measured, 158 MB |
| Tester build | release plus `--dart-define=REVIEW_BUILD=true` | opens every paid area and shows onboarding on every launch. Compile-time switch, false in every normal build, never for the store |

```
source tool/lib.sh && load_defines && rm -rf build/ios/iphoneos/Runner.app
flutter build ios --release --no-pub ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"} --dart-define=REVIEW_BUILD=true
A=build/ios/iphoneos/Runner.app
ls $A/Frameworks/App.framework/flutter_assets | grep -c kernel_blob     # must print 0 (release)
security cms -D -i $A/embedded.mobileprovision | grep -c <udid>         # must print 1
xcrun devicectl device install app --device <udid> $A                   # installs OVER the old app, data stays
xcrun devicectl device process launch --device <udid> com.thoufeekx.frenchtutor
```

Drop `REVIEW_BUILD` for a normal build. Installing the same bundle id over itself
keeps sign-in and progress. Never uninstall to "refresh".

## 11. Commit and push

1. `tool/check.sh --quick` (and `tool/check.sh` before a push). Fails only on NEW issues.
2. Secret scan of new and changed text files (keys, `service_role`, private keys).
3. Look at sizes. Do not commit large exploration folders (the 135 MB `docs/v3/branding/` is kept out on purpose).
4. Commit in pieces: content sources, generated content, app code, tests, docs.
5. Push only when the owner asks. A rejected first push because of the build-number hook is normal: run it again.

## 12. How an agent should think (the rules behind the speed)

- **Evidence before action.** A claim about the app is true only if a tool result from this session shows it: a log, a screenshot, source, a test run.
- **Cheapest proof first.** Mac before phone, a pure function before a widget, a filter before a full walk.
- **Do not rerun what passed.** Rerun only a test that failed, and only after you fixed the cause.
- **80/20.** A few tests that cover each stage and each new screen beat a full hour-long walk. Say plainly what you did not verify.
- **Classify the failure** (test, app, or load) before you change a line.
- **One heavy job at a time**, and name what you are waiting for.
- **Be honest in reports.** "Not tested on a device" is a useful sentence. A green summary that hides a skipped check is not.
- **Back up before anything that deletes or regenerates many files**, and prefer a throwaway copy.
- **Never claim a push, a install, or a launch succeeded unless the tool output says so.**

## 13. Copy-paste prompt for another AI IDE

```
Read docs/v3/README.md, then docs/v3/FAST_TESTING_PLAYBOOK.md and docs/v3/AGENT_RULES.md.
Follow the playbook exactly: run the section 1 checklist, prove on the Mac first, use one
heavy job at a time, run a device test only if the change needs a phone, look at every
screenshot, classify each failure, and never rerun a test that passed. Task: <your task>.
Do not push unless asked.
```
