# V3 build structure

V3 is a restructure of the shipped app, not a new app. Same bundle ID
(`com.thoufeekx.frenchtutor`), same Supabase project, same RevenueCat
products and subscribers. Branch: `tcf-v3`. Restore point: tag
`pre-v3-2026-10-12`.

## Principles

1. Reuse first. A v3 screen composes existing primitives (`LearningCard`,
   `PrimaryActionButton`, `DesignTokens`, the lesson renderers) before any new
   widget exists.
2. Content is data, not code. Lessons live in `content/tcf/` and ship through a
   shared catalog. Adding a unit never needs an App Store review.
3. No generation on the learner's request path. The app plays authored content.
   Gemini Live is used for voice (Marie) only.
4. Nothing is deleted until its replacement passes an on-device test. Old
   screens stay compiled, unreachable from v3 navigation, then are removed in a
   dedicated commit.
5. Small commits on `tcf-v3`, each passing `tool/check.sh`.

## Repository layout (target)

```
FrenchTutor/
  AGENTS.md                    always-on rules, points here
  docs/v3/                     these rules + generated SCREEN_MAP.md
  content/tcf/
    syllabus/                  stages, units, word ledger, grammar index
    units/                     authored lesson files, one folder per unit
    audio/                     audio manifests (every French string to bake)
    schema/                    JSON schemas
    tools/validate.py          the content gate
  flutter_app/
    lib/v3/                    NEW screens and shell (keys + semantics enforced)
      shell/                   tab bar, routing
      onboarding/ today/ path/ lesson/ marie/ mocks/ progress/ paywall/
    lib/design/                tokens, theme (re-theme here, once)
    lib/services/              reused: Live audio, SRS, sync, RevenueCat
    integration_test/          on-device tests + support/probe.dart
    test_driver/               host driver for flutter drive
    tool/                      check.sh, e2e.sh, device.sh, screen_map.py
  supabase/                    migrations and functions
```

## Navigation

Five tabs: Today, Path, Marie, Mocks, Progress. Routing goes through
`AppRouter` only, never raw route construction. Old screens are reachable only
from Settings > Legacy while they exist.

## Audio

All learner audio is baked once through the existing Gemini Live path in the
tutor's voice and stored in one shared public catalog (the pattern of
`alphabet_audio_catalog`). No per-user audio copies, no TTS provider. The
speaker button resolves: local file, then shared catalog, then (miss only) live
generation and upload to the shared catalog. Cache key includes text, voice and
a version prefix so a changed script never plays stale audio.

## Entitlements and review safety

- Free: Stage 0 sounds, A1 Unit 1, one short TCF listening set, first level
  estimate. Paid: everything after, Marie minutes, mocks.
- Debug bypass `dev_force_pro_unlock` exists only under `kDebugMode`.
- Every submission: specific Notes for Review (guideline 2.3.1/2.3.12), working
  demo login, screenshots that match the build, price shown as the total billed
  amount, Restore, Terms, Privacy, AI consent naming Google, account deletion.
- No `TCF` or `FEI` in the app name. Add "independent, not affiliated with FEI
  or IRCC".

## Simulator unlock (planned)

`google_mlkit_text_recognition` and `google_mlkit_commons` have no arm64
simulator slice, so the app cannot build for the iOS simulator today. Photo
tutor is out of scope for v3. Removing those two packages and the scan screens
lets Xcode's MCP `DeviceInteraction*` tools (tap, swipe, screenshot,
hierarchy on iOS 27+ simulator) drive the app without a phone.

## Build and release

- Device iteration: `tool/device.sh run` (debug, hot reload) or
  `tool/e2e.sh`.
- Version bump: `bump_build_number.sh`. No pre-push hook exists now; bump
  explicitly when preparing a TestFlight build.
- Never commit secrets. `.env`, `secrets.local.properties` and keystores stay
  local. A copy of the current ones lives in `~/Backups/` (owner-only).
