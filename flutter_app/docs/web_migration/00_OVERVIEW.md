# Web Migration — Overview

**Goal**: serve the existing Flutter app (currently shipping on iOS, locked as Phase 1 at commit `9c61e31`,
build 93) as a web app too, from the same codebase, hosted on Vercel, reachable via a sign-up/login button on
the existing marketing landing page. Landing page itself is untouched (stays static, optimized for SEO).

**Constraint that shapes every decision below**: one developer + an AI coding agent must be able to maintain
this long-term. That means we are not maintaining three codebases or three mental models — we are maintaining
one codebase with a small number of clearly-named platform seams. See the root [`CLAUDE.md`](../../CLAUDE.md)
for the abstraction rule this plan follows.

## Phase index

| Phase | File | What it covers | Status |
|---|---|---|---|
| 1 | [01_phase1_compatibility_audit.md](01_phase1_compatibility_audit.md) | File-by-file audit: what's shared as-is, what needs a thin platform shim, what needs real new code | **Not started** |
| 2 | [02_phase2_auth_and_payments.md](02_phase2_auth_and_payments.md) | Web sign-in (Supabase OAuth) and web payments (Stripe vs RevenueCat Web Billing) | Not started |
| 3 | [03_phase3_database_and_storage.md](03_phase3_database_and_storage.md) | Drift web backend (IndexedDB via `drift/wasm`), sync-vs-local-cache tradeoff | Not started |
| 4 | [04_phase4_voice_and_realtime.md](04_phase4_voice_and_realtime.md) | The live voice call (Gemini Live) on web — the one subsystem that's a real rewrite, not a port | Not started |
| 5 | [05_phase5_deploy_and_hosting.md](05_phase5_deploy_and_hosting.md) | Vercel deploy pipeline, domain structure, dart-define/secrets handling | Not started |

Work through phases roughly in order — 2 and 3 can run in parallel with each other, but both should land before
4, and 4 must be functionally complete before 5 goes to production (no point deploying a web app whose
flagship voice feature doesn't work).

## Non-negotiables carried over from the iOS build

These already work and are already tested on iOS. Web must match, not compromise:

- Full lesson pipeline: grammar lab, writing lab, connectors lab, alphabet lab, liaison lab, story reader,
  flashcard sessions — all screens, unchanged, reused directly on web (they're pure Flutter UI, no native
  plugin dependency).
- SRS scheduling, competency graph, evidence-based mastery tracking — pure Dart, already 100% portable.
- The live AI voice call experience — must work on web too, see Phase 4. This is the hardest one; budget it
  as its own mini-project, not a checkbox.
- Visual polish / native-feel interaction patterns (see `.claude/skills/ui-patterns` and
  `.claude/skills/design-system`) — these apply on web too. A web app that merely "compiles" but looks like
  an unstyled web page is not an acceptable Phase 1 web outcome.

## What does NOT need to be perfectly identical

- Payment mechanism (RevenueCat IAP on iOS vs Stripe/web billing on web) — different backend, same user-facing
  entitlement model, see Phase 2.
- Offline-first local database on iOS vs a possibly thinner, more server-reliant model on web, see Phase 3.
- Native permission dialogs vs browser permission prompts — cosmetic difference only.

## Working agreement for whoever (human or agent) picks this up

1. Before writing platform-specific code, check whether the "shared vs platform-specific" boundary already
   exists for that subsystem. If it doesn't, create the interface first, migrate the existing iOS/Android
   implementation behind it with **no behavior change**, verify `flutter test` still passes, *then* add the
   web implementation. Don't add web code and an interface in the same commit as unrelated refactors.
2. Update the phase file's status line when you start or finish a chunk of work, so the plan reflects reality.
3. Local web dev: `./run_web_with_keys.sh` (reads `secrets.local.properties`, launches
   `flutter run -d web-server --web-port 8734`). Configured in `.claude/launch.json` as `flutter-web-debug`.
4. Never touch RevenueCat/native sign-in/native audio code paths while doing web work — those are Phase 1
   iOS, locked and shipping. Web gets its own implementation behind the shared interface; iOS's existing
   implementation is not something to "improve" along the way.
