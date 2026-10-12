---
name: parlesprint-v3-workflow
description: Fast, evidence-based workflow for building, testing and running ParleSprint v3 (TCF Canada) on the connected iPhone. Use for any code change, screen, test, device run or build in flutter_app/. Prevents assumed UI and trial-and-error loops.
triggers:
  - user
  - model
allowed-tools:
  - read
  - grep
  - glob
  - exec
  - edit
---

# ParleSprint v3 workflow

Read `docs/v3/AGENT_RULES.md` and `docs/v3/TESTING.md` first, then act. All
commands run from `flutter_app/`.

## The loop

1. Locate: `python3 tool/screen_map.py --find <screen or label>`, then read the
   source file. Do not assume keys, labels or routes.
2. Observe: if the screen's on-device behavior matters, run
   `tool/e2e.sh integration_test/explore_test.dart` (or a one-screen probe) and
   read `artifacts/e2e/probe.json` and `artifacts/e2e/shots/*.png`.
3. Change: smallest edit that reuses existing primitives. Every interactive
   widget under `lib/v3/` gets `ValueKey('<screen>.<element>')` and a Semantics
   label on the control itself.
4. Gate: `tool/check.sh --quick`, then `tool/check.sh <test files>`.
5. Prove on device: `tool/e2e.sh integration_test/<name>_test.dart`, written
   against labels the probe listed. Look at the screenshot.
6. Record: `python3 tool/screen_map.py` to refresh `docs/v3/SCREEN_MAP.md`,
   then commit one concern at a time on `tcf-v3`.

## Hard rules

- No `pumpAndSettle` in this app. Use `probe.settle`.
- Tap with `probe.tapLabel`. Semantics rects are physical pixels.
- Never assign `binding.reportData`; use `probe.capture`.
- Never run a purchase flow. Payments are bypassed only by the debug key
  `dev_force_pro_unlock`.
- One heavy job at a time; scripts refuse a second. Two failed attempts on the
  same problem: stop, report facts, ask.
- If a formatter or generator touches unrelated files, revert those files.
- Never push unless asked. Never commit secrets.

## Useful measured numbers

Cold device build ~72s, warm 23 to 33s, whole e2e run 90 to 145s, analyze ~7s.
Probe rects are physical pixels (about 3x logical on kodekarbon).
