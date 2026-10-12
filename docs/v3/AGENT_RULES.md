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
