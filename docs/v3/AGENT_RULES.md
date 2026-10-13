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

- Two failed attempts at the same problem: stop, summarize the facts, ask.
- One heavy job at a time (`flutter run`, `flutter drive`, `xcodebuild`,
  Gradle). The scripts refuse to start a second one. Machine has 16GB.
- At most one simulator booted. Prefer the connected iPhone.
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

## 7. A tutor must never hear herself (hard rule, everywhere)

The microphone must send **nothing** to a model while the phone is making sound:
the tutor's voice, the tail after it, and any clip the app plays itself (a
lesson speaker button, story narration). This holds on the loudspeaker, the
earpiece, AirPods and wired headsets alike. Do not rely on the route or on the
model to notice. A tutor that praises her own voice is a bug.

- All of it goes through `lib/services/mic_echo_gate.dart` (`MicEchoGate`, tail
  900 ms) and `AudioStreamingService.blockMicUntil`.
- Anything that plays audio while a call can be open must close the mic for the
  clip's length plus the tail. `LessonSpeechService.playBytes` already does, and
  `InlineCallController` listens (`LessonSpeechService.clipEndsAt`). A new audio
  path must do the same, or use the controller's external-playback bridge.
- Prompts say it too (`compactLessonCoach`: "your own voice is not the learner").
  That is a second line of defence, never the first.
- Keep `test/mic_echo_gate_test.dart` green. Do not shorten the tail to make the
  app feel faster. Learners get a Skip button instead.

## 8. Speaker buttons and Marie's memory (how the old app did it, and why)

- **A speaker button asks the tutor to say the exact line** (`V3MarieSession.speak`). It does not play a saved clip and never builds one on tap. The old vocabulary lessons worked this way: one warm Live connection, a tiny "say exactly this" command, always the voice the learner chose. A tap connects her muted with no hello, so a speaker tap never opens the microphone.
- **The screen she knows about must never be frozen.** `GeminiLiveService.lessonContextBuilder` is read on every setup and reconnect. A fixed string made her describe an old word after a reconnect.
- **A reconnect must keep the conversation.** `V3LiveMarieSession` adds the last six lines (`CALL MEMORY`) on every connect, and the prompt says the call is continuing, so she never greets again.
- **The server resets a connection about every ten minutes** (goAway). For the lesson coach the swap waits until she finishes her sentence, and up to three bounded reconnects are allowed.
- **An unanswered listening line is heard but never shown** (`speak(reveal: false)`), so the pill cannot give the answer away.
- **Every word the learner studies has an example sentence.** `check_book.py` fails the build otherwise.
