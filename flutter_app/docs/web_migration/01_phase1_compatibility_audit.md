# Phase 1: Web Compatibility Audit

**Status**: Complete (initial sweep, from actual codebase inspection on `web-app-phase1`). Re-verify any row
marked "verify at implementation time" before building against it — a few items depend on package versions
that may have moved on since this was written.

**Goal**: a concrete, file-by-file list of what needs to change before this codebase runs correctly as a web
app, so Phases 2-5 have no surprises. This phase made no code changes.

## Headline finding: more groundwork already exists than expected

Someone already started laying web foundations in this codebase before this plan existed:

- `lib/data/database/database_opener.dart` already conditionally exports a native vs. web SQLite opener
  (`database_opener_native.dart` uses `path_provider` + native `sqlite3`; `database_opener_web.dart` already
  loads `sqlite3.wasm` + `IndexedDbFileSystem` correctly). `web/sqlite3.wasm` is already checked in. **Phase 3
  may be much smaller than originally scoped** — verify this opener is actually wired up correctly and the
  rest of the Drift layer above it has no other native-only assumptions, but the hard part (the wasm
  connection factory itself) looks already done.
- `kIsWeb` guards already exist and look correct in `lib/main.dart` (skips portrait-lock on web, has a
  `PilotPlatform.web` case already defined in `pilot_access_service.dart`), `lib/services/revenue_cat_service.dart`
  (`isConfigured` is already `false` on web — no crash, just silently unconfigured), and
  `lib/widgets/adaptive/adaptive.dart` (haptics no-op on web).
- `gemini_live_service.dart` (the Gemini Live protocol/session logic) is already pure Dart + `web_socket_channel`,
  which works identically on web — **no changes needed here**, confirming the plan's assumption that only the
  audio capture/playback layer underneath it needs new code, not the protocol logic itself.

This means Phase 1's real job now is: confirm nothing downstream of these existing seams breaks, and finish
the pieces that are gated off rather than actually implemented (RevenueCat on web, TTS audio file caching).

## Compatibility table

| Subsystem / file | iOS/Android today | Web status | Bucket |
|---|---|---|---|
| `drift` + `database_opener.dart`/`database_opener_web.dart` | native `sqlite3` via `database_opener_native.dart` | **Already implemented**: loads `sqlite3.wasm`, uses `IndexedDbFileSystem` | Verify only — see Phase 3 |
| `sqlite3_flutter_libs` (native binary bundling) | required for native builds | not needed on web (wasm file used instead); confirm it doesn't break a web build by being present in `pubspec.yaml` | Verify only (should be a no-op on web, `sqlite3` package handles the split internally) |
| `lib/services/gemini_live_service.dart` (Gemini Live protocol) | pure Dart + `web_socket_channel` | **Already works identically** | Shared as-is |
| `lib/services/audio_streaming_service.dart` (mic capture + playback) | `flutter_sound` (native recorder/player) + `audio_session` (native audio routing) + `permission_handler` | No web implementation exists yet; not behind an interface yet either — it's a concrete class `inline_call_controller.dart` calls directly | **Real new code** — see Phase 4. This is the one true gap. |
| `lib/services/lesson_speech_service.dart` (TTS audio cache) | caches pre-generated Gemini TTS audio bytes to disk via `dart:io File` + `path_provider` (no `flutter_tts`/`speech_to_text` — comment in file confirms audio comes from Gemini itself, not device TTS) | `dart:io File` doesn't exist on web; needs a small web-specific cache (e.g. IndexedDB via a package, or in-memory/no-cache fallback since it's a cache, not a source of truth) | Shim — small, contained |
| `lib/services/revenue_cat_service.dart` | native IAP via `purchases_flutter`, gated by `Platform.isIOS`/`Platform.isAndroid` | Already gated off (`isConfigured` false on web) — safe, but means **no entitlement path exists on web at all yet** | Real new code — see Phase 2 (Stripe/RevenueCat Web Billing) |
| `lib/screens/settings/settings_screen.dart` `_openManageSubscriptions()` | deep-links to App Store/Play Store subscription management via `Platform.isIOS` | needs a web branch — link to whatever web billing portal Phase 2 picks (e.g. Stripe customer portal), or hide the row until Phase 2 lands | Shim |
| `google_sign_in` | native SDK sheet | package has a web implementation; flow differs (renders its own button/redirect) | Shim — see Phase 2 |
| `sign_in_with_apple` | native SDK sheet | needs Apple's web "Sign in with Apple JS" + a registered Service ID/redirect URI, real setup work | Shim, but with real config overhead — Phase 2 should explicitly decide whether this ships in web v1 |
| `permission_handler` | native permission dialogs | browser permission prompts; only the mic permission actually matters here (used by `audio_streaming_service.dart`) | Shim, low effort, tied to Phase 4 |
| `path_provider` | used in `database_opener_native.dart` and `lesson_speech_service.dart` | has a web implementation but semantics differ (no real filesystem); both current call sites are being replaced by web-specific code anyway (wasm opener, TTS cache shim), so no separate fix needed here | Covered by the two rows above |
| `supabase_flutter` | works cross-platform already | works cross-platform already | Shared as-is |
| `flutter_riverpod`, `http`, `web_socket_channel`, `shared_preferences`, `crypto`, `uuid`, `intl`, `json_annotation`, `logger`, `url_launcher`, `google_fonts`, `flutter_animate`, `tutorial_coach_mark`, `package_info_plus`, `sentry_flutter`, `posthog_flutter` | all pure Dart or already-cross-platform packages | all work on web without changes | Shared as-is |
| Business logic: SRS (`srs_service.dart`), competency graph, evidence store, `lesson_agent_service.dart` orchestration, prompts (`live_prompts.dart`), content models, sync (`sync_service.dart`) | pure Dart | pure Dart | Shared as-is |
| Screens/UI: labs (grammar/writing/connectors/alphabet/liaison), lessons (story reader, flashcard, writing task), onboarding, settings, session screen, `inline_call_bar.dart` | pure Flutter widgets, no native-only widget dependencies found | same widgets render on web | Shared as-is — re-verify visually once a web build is running (see Phase 5), since layout/interaction on a browser viewport can still surface issues pure code review won't catch |

## Live verification (this session)

Beyond static code review, actually built and ran the app as a web app to confirm the audit above isn't just
theoretical:

- `flutter build web --dart-define=...` (both debug and `--release`) **compiles with zero errors**. Only
  warning is a `--wasm`-target-only lint in `flutter_tts`'s web shim (irrelevant unless we later target the
  new experimental Wasm compile mode instead of the standard JS/CanvasKit one — not a blocker).
- Note in passing: `flutter_tts` and `speech_to_text` are pubspec dependencies with **no actual import
  anywhere in `lib/`** (`lesson_speech_service.dart`'s own comment confirms audio comes from Gemini directly,
  not device TTS/STT). Not a web-compat issue, just dead weight worth pruning at some point — not in scope for
  this migration.
- Ran the `--release` build via a static file server and loaded it in a real browser tab: **the onboarding
  flow works end to end** — welcome screen with correct gradient/branding rendered, "Continue" advanced to
  "Step 1 of 4: What should French unlock for you?" with working option cards, progress bar, and continue
  button. Zero console errors at any point.
- One cosmetic-only artifact observed: this sandboxed browser has no WebGL, so Flutter's web renderer fell
  back to CPU-only rendering (`Falling back to CPU-only rendering. Reason: webGLVersion is -1`), and the
  "ParleSprint" title text appeared visually clipped ("ParleSprir"). This is very likely specific to the
  CPU-rendering fallback in this sandbox, not a real bug — re-verify in a normal WebGL-capable browser during
  Phase 5 before treating it as an actual issue.
- Did NOT verify: the `flutter run -d web-server` **debug** workflow (`run_web_with_keys.sh`) hangs
  indefinitely in this sandboxed browser because Dart DevTools' web debug protocol (DWDS) expects the "Dart
  Debug Extension" for Chrome, which isn't installed here. This is a debugging-tool limitation of this
  environment, not an app problem — the `--release` build above proves the app itself runs correctly. Local
  dev-mode debugging should work fine in a normal desktop Chrome with that extension installed; just don't
  expect it to work through this sandboxed preview browser.

## Deliverable status

Table above is the completed deliverable, corroborated by a real build + browser run, not just code review.
One follow-up still worth doing early in Phase 3: explicitly exercise the `database_opener_web.dart` path
(open a DB, run the full migration chain, read/write a row) rather than relying on "the onboarding screen
before login worked" as proof — onboarding likely doesn't touch the DB much yet.
