# Phase 6: Deploy & Hosting

**Status**: Not started. Only start this once Phase 5 (voice) is functionally complete — there is no value in
deploying a "high-end web app" whose flagship feature doesn't work; that undermines the whole pitch to users
landing on it from the marketing site.

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
