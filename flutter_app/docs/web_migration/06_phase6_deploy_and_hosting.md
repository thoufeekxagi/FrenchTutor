# Phase 6: Deploy & Hosting

**Status**: **Config written and committed; the deploy itself needs your Vercel/Supabase/Google consoles.**

See **[`DEPLOY_WEB.md`](DEPLOY_WEB.md)** for the actual step-by-step. Committed in `flutter_app/`:

- `vercel.json` — build/output config, SPA rewrites, cache headers, and security headers (including
  `Permissions-Policy: microphone=(self)` so live calls are allowed and camera/geolocation are not).
- `install_flutter_vercel.sh` — installs a **pinned** Flutter SDK (3.44.4), since Vercel's build image has
  none. Pinned on purpose: an unpinned SDK lets a Flutter release break production with no change on our side.
- `build_web_vercel.sh` — `flutter build web --release` with every `--dart-define` sourced from Vercel env
  vars, failing fast with a clear message if `SUPABASE_URL`/`SUPABASE_ANON_KEY` are missing.

Set **Root Directory = `flutter_app`** in Vercel; the config is not at the repo root.

**Blocking issue for public launch**, documented at the bottom of `DEPLOY_WEB.md`: `--dart-define` values are
compiled into the JS bundle and publicly readable. `SUPABASE_ANON_KEY` is fine by design; `GEMINI_API_KEY` and
`OPENROUTER_API_KEY` are not, and would be extractable and billable by anyone. Fine for a private/invite-only
deploy, not for open signup. Fix is to move those calls behind a Supabase edge function.

## Real bug found and fixed: blank white screen from CanvasKit CDN dependency

Live-tested in Safari on the founder's Mac and found the actual cause of an early "just a blank white page"
report. `flutter build web` by default loads its rendering engine (CanvasKit) from `www.gstatic.com` at
**runtime**, not from the copy it already bundles locally in `build/web/canvaskit/`. If that CDN request fails
for any reason — ad blocker, corporate network, some VPNs, an offline dev machine — the app silently never
paints anything. No error banner, no console message visible without deliberately hooking `window.onerror`.

Fixed with the `--no-web-resources-cdn` flag (confirmed via Flutter SDK source:
`useLocalCanvasKit = !useCdn`, wired to `buildConfig.useLocalCanvasKit` in the generated
`flutter_bootstrap.js`). Now baked into `build_web_vercel.sh` and `run_web_with_keys.sh` so every build and
every local dev run gets it, not just this one debugging session.

Diagnosis method, in case a similar silent-blank-page report recurs: `window.onerror` and
`unhandledrejection` don't fire until something is hooked *before* the failure happens, so add a small inline
`<script>` at the top of `build/web/index.html` that writes to `localStorage` on error, reload, then read
`localStorage.getItem(...)` after — this survives a full page reload, unlike an in-memory JS variable set via
one-off `do JavaScript` calls (which get wiped by navigation).

## Separate, unrelated finding: transient WebGL context loss is not an app bug

While debugging the above, encountered a second, different failure signature
(`LateInitializationError` inside the engine's `onContextLost` handler) that persisted even after the CDN fix.
Isolated it with a minimal test — a bare `document.createElement('canvas').getContext('webgl2')`, no Flutter
code involved — which came back with `isContextLost() === true` immediately. That proves it was the browser's
WebGL context budget being exhausted (heavy tab count / GPU load on the test machine at the time), not
anything in this codebase. Quitting and relaunching the browser (or restarting the machine) clears it. Noting
this here so it isn't mistaken for an app bug and re-debugged from scratch next time it's seen.

CI is still not set up — a web-breaking change can currently reach production unnoticed.

## Domain / site structure

- Marketing/landing page: stays exactly as it is today, on its current domain, optimized for SEO. Not
  touched by this migration.
- A "Sign up" / "Log in" button on the landing page links to the app subdomain, e.g. `app.<domain>.com`.
- The app subdomain serves the Flutter web build as its own separate Vercel project — fully decoupled build
  pipeline from the landing page, so a landing-page content update never risks breaking the app deploy and
  vice versa.

## Build & deploy

- `flutter build web --release` with the same `--dart-define` keys currently passed by
  `run_web_with_keys.sh` / `bump_build_number.sh`'s Xcode config-generation step — same secrets source
  (`secrets.local.properties` locally; Vercel environment variables in production), same keys
  (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY`, etc., plus whatever Phase 3/4 additions Stripe or
  new audio config require).
- Output of `flutter build web` is static (HTML/JS/wasm) — deploys to Vercel as a static site. No server
  runtime needed unless a phase above introduces one (e.g. a Stripe webhook handler, which would be a small
  separate Vercel serverless function, not part of the Flutter build).
- Set up a Vercel project pointing at this repo (or a subdirectory/branch, depending on how the marketing
  site's own repo is structured) with build command `flutter build web --release --dart-define=...` and output
  directory `build/web`.

## CI recommendation

Add a build matrix (even a minimal one) that runs `flutter analyze`, `flutter test`, and `flutter build web`
on every PR touching `lib/` — catching a web build break at PR time, not after a Vercel deploy fails. This is
what makes "one developer + an AI agent, no dedicated web specialist" actually sustainable: regressions get
caught automatically instead of relying on someone remembering to test three platforms by hand.

## Deliverable

- Vercel project live at `app.<domain>.com`, auto-deploying from the appropriate branch.
- Landing page's sign-up/login button pointing at it.
- (Recommended) CI check that fails a PR if `flutter build web` breaks.
