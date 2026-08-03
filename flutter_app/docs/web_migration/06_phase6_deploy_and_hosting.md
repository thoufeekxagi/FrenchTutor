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
