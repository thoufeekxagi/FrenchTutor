# V3 agent operating rules (for Devin/Claude working in this repo)

Read this first, every session. It exists because earlier sessions assumed
things about the app, failed, then fixed and retried. The cost was time. These
rules replace guessing with evidence.

## 1. Evidence before action

- A claim about the app is true only if a tool result in this session shows it:
  probe JSON, screenshot, screen map, source file, test output.
- Before touching a screen: `python3 flutter_app/tool/screen_map.py --find <x>`,
  then read the file.
- Before writing a test: run the explorer or a probe and read the output.
- Before editing a generator, formatter or script output: check `git status`
  after, revert anything unrelated.
- Never "try it and see" on a device. Tier 0 and Tier 1 (docs/v3/TESTING.md)
  come first, every time.

## 2. Loop discipline

- Persist until the user's requested outcome is complete. A failed attempt is
  evidence for changing the diagnosis or implementation, not a reason to stop.
  Ask only when progress depends on information or access the user must provide.
- One heavy job at a time (`flutter run`, `flutter drive`, `xcodebuild`,
  Gradle). The scripts refuse to start a second one. Machine has 16GB.
- At most one simulator booted. For simulator work, use the dedicated iPhone
  17 Pro through `flutter_app/tool/simulator.sh`; its commands shut down other
  booted simulators and verify that only the selected simulator remains.
- Simulator iteration is Debug/developer builds only. Do not use Profile or
  Release in this workflow.
- If the simulator runtime or app launch becomes unstable or noticeably laggy,
  `tool/simulator.sh reset` may erase and restart the dedicated simulator. The
  owner explicitly authorized wiping simulator-local data for this recovery.
  Use reset for simulator runtime/device problems, not compile or assertion
  failures.
- Never kill a process you did not start without the user's say. Orphaned
  `flutter drive` and `lldb` from aborted runs may be stopped on request.
- Dev data is disposable: reset instead of debugging local state.

## 3. Work order for any task

1. State the screen or unit contract (UI_STRUCTURE.md, CONTENT_AUTHORING.md).
2. Make the smallest change reusing existing primitives.
3. `tool/check.sh --quick`, then targeted tests.
4. Device proof: `tool/e2e.sh` with a test written from probe facts.
5. Look at the screenshot. Update SCREEN_MAP.md. Commit.

## 4. Git and safety

- Branch `tcf-v3`. Restore point: tag `pre-v3-2026-10-12`. Never force-push,
  never rewrite history, never delete branches.
- Commit small, one concern per commit, message explains why.
- Never commit secrets (`.env`, keystores, keys). Local copies in `~/Backups/`.
- No destructive command without explicit user confirmation for that action.
- Do not push unless asked.

## 5. App Store safety

Same bundle ID. Specific review notes. Screenshots match the build. No
unverifiable claims, no "official" language, no guaranteed scores. Total price
dominant on the paywall. See BUILD_STRUCTURE.md.

## 6. Where things are

- Rules: `docs/v3/*.md` (this folder). Skills: `.devin/skills/`.
- Fast scripts: `flutter_app/tool/` (`check.sh`, `e2e.sh`, `device.sh`).
- On-device tests: `flutter_app/integration_test/` (`support/probe.dart`).
- Artifacts of the last device run: `flutter_app/artifacts/e2e/` (ignored).
- Content: `content/tcf/`. Validator: `content/tcf/tools/validate.py`.
- Old design skill `parlesprint-product-design` predates v3. Where it
  conflicts with `UI_STRUCTURE.md` (palette), v3 wins.

## 7. Echo control and learner interruption

The model must not receive tutor echo as learner speech. The interactive
lesson and Live Tutor support natural interruption through an audio path with
acoustic echo cancellation and noise suppression:

- On iOS, capture and tutor playback share the `VoiceProcessingIO` audio unit in
  `ios/Runner/VoiceProcessingAudioPlugin.swift`. Full duplex is active only if
  the native engine confirms voice processing. If it fails, fall back to the
  existing half-duplex route.
- On Android, these calls use `AudioSource.voice_communication` with the
  platform's echo-cancellation and noise-suppression effects. Do not assume a
  route has AEC if the platform path is unavailable.
- `VoiceActivityGate` adds client-side speech confirmation and a short pre-roll,
  then sends the utterance endpoint. Gemini Live VAD remains enabled as a
  second decision layer. Silence and short clicks stay off the billable stream.
- The V3 route does **not** mute the mic for tutor output. A confirmed learner
  interruption stops local playback and is sent to Gemini. A known app-owned
  clip still uses `AudioStreamingService.blockMicUntil` for its measured length
  plus the 150 ms output tail.
- If AEC/NS cannot start or recover, disable full duplex before any mic frames
  are sent; use the half-duplex fallback. Do not send raw unprocessed speaker
  audio in an attempt to preserve barge-in.
- Run `test/voice_activity_gate_test.dart`, `test/mic_echo_gate_test.dart`,
  and the device `integration_test/voice_processing_test.dart`. The fake Marie
  test validates lesson UI only; it is not evidence of acoustic quality.

## 8. Speaker buttons and Marie's memory (how the old app did it, and why)

- **A speaker button asks the tutor to say the exact line** (`V3MarieSession.speak`). It does not play a saved clip and never builds one on tap. The old vocabulary lessons worked this way: one warm Live connection, a tiny "say exactly this" command, always the voice the learner chose. A tap connects her muted with no hello, so a speaker tap never opens the microphone.
- **The screen she knows about must never be frozen.** `GeminiLiveService.lessonContextBuilder` is read on every setup and reconnect. A fixed string made her describe an old word after a reconnect.
- **A reconnect must keep the conversation.** `V3LiveMarieSession` adds the last six lines (`CALL MEMORY`) on every connect, and the prompt says the call is continuing, so she never greets again.
- **The server resets a connection about every ten minutes** (goAway). For the lesson coach the swap waits until she finishes her sentence, and up to three bounded reconnects are allowed.
- **An unanswered listening line is heard but never shown** (`speak(reveal: false)`), so the pill cannot give the answer away.
- **Every word the learner studies has an example sentence.** `check_book.py` fails the build otherwise.

## 9. Real progress versus looking around (one rule for Resume)

- `V3Progress` (`lib/v3/lesson/v3_course.dart`) is the only place that knows where Resume goes. Do not add a second progress store.
- **Frontier** = the furthest step reached in an unfinished lesson. It only moves forward (`advanceFrontier`). Going back, reviewing, replaying or reopening never lowers it.
- **Review** is free: the lesson player has a Previous button, a "Reviewing. Your progress is at step N" line with "Go to step N", and earlier questions can be skipped. An answered question shows its answer again when you come back.
- **Replay** of a finished lesson (`reviewAll`) changes nothing. Finished lessons never get a frontier, and replaying does not move the path (`lastCompleted` is set only the first time).
- **Resume order** (`V3Progress.pickNext`): the unfinished lesson last moved forward in, else the first unfinished lesson after the one finished last, else any left behind.
- **Path rows:** unfinished with progress asks "Resume at step N" or "Review from the start". Finished says "tap to replay".
- Stories keep their own free-reading position and are not part of this rule.

