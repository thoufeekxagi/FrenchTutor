# FrenchTutor (ParleSprint) — Flutter App

AI French tutor: speak and learn French on the go. Single Flutter codebase targeting iOS, Android, and Web.

## Phase 1 status: LOCKED

The iOS app as of commit `9c61e31` (build 93) is the locked Phase 1 go-to-market baseline. It has been
verified (`flutter analyze` clean, `flutter test` 191/192 passing — the one pre-existing failure in
`test/widget_test.dart` is unrelated to recent work and was confirmed failing on master before any of this
round's changes). **Do not refactor or "clean up" Phase 1 iOS code paths as a side effect of web work.**
Bugs found post-launch get fixed directly; they are not an excuse to restructure things that already work.

## Current initiative: Web app (Phase 1 of the *web* migration — see docs/web_migration/)

We are extending the same codebase to serve a web app (hosted on Vercel), reachable from a sign-up/login
button on the existing marketing landing page. **This is a web build of the existing app, not a rewrite.**

The full phased plan, with a subsystem-by-subsystem compatibility audit and concrete package/architecture
choices, lives in [`docs/web_migration/`](docs/web_migration/00_OVERVIEW.md). Read that before touching any
web-related code — it is the source of truth for what's been decided, what's in progress, and what's still
open. Update the relevant phase file's status section as work completes; don't let this plan go stale.

## The one rule that keeps this maintainable by one developer + an AI agent

**Never fork the app. Only fork the leaf-level service implementation.**

Business logic (SRS, competency graph, lesson agent orchestration, prompts, content models, screens/UI) is
platform-agnostic and must stay in one shared file, used identically on iOS/Android/web. Only a small number
of leaf services are genuinely platform-coupled (database connection, auth sign-in trigger, audio streaming,
payments). Those get ONE abstract interface with platform-specific implementations selected via Dart's
conditional-import mechanism (`import 'x_native.dart' if (dart.library.js_interop) 'x_web.dart';`) — never an
`if (kIsWeb)` branch scattered through business logic, and never a parallel copy of a whole screen or service.

If you find yourself about to duplicate a screen, a service, or a chunk of business logic "for web," stop —
that's a sign the abstraction boundary is in the wrong place. Go back to
[`docs/web_migration/00_OVERVIEW.md`](docs/web_migration/00_OVERVIEW.md) and find (or create) the right seam.

## Ground rules (apply to all platforms)

- No em dashes anywhere in UI copy or AI-generated output — it reads as AI-generated. Use periods, commas, or
  parentheses instead.
- Palette: active theme is `ProSystemAzure` (azure/teal/navy) — see `lib/theme/palettes.dart`.
- Copy the *structure* of reference apps (Readle) for UX patterns; never copy their colors.
- `flutter analyze` and `flutter test` must be clean (module of the one known pre-existing failure above)
  before any branch merges to `master`.
- Every push auto-bumps the iOS build number via `.git/hooks/pre-push` + `bump_build_number.sh` — this is
  expected; if a push is rejected once with "run git push again," that's normal, just retry.
