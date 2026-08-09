# Deploying the web app to Vercel

Everything in this repo is ready. What remains is console configuration in Vercel, Supabase, and Google
Cloud, which needs your accounts and cannot be done from the codebase.

Read the **Before public launch** section at the bottom before opening signup to strangers. There is one real
security issue there.

---

## 1. Vercel project

The repo root for the app is `flutter_app/`, and the committed config lives there:

| File | Purpose |
|---|---|
| `vercel.json` | Build/output config, SPA rewrites, cache and security headers |
| `install_flutter_vercel.sh` | Installs a **pinned** Flutter SDK (3.44.4) — Vercel's image has none |
| `build_web_vercel.sh` | Runs `flutter build web --release` with `--dart-define`s from env vars |

In Vercel:

1. **New Project** → import `thoufeekxagi/FrenchTutor`.
2. Set **Root Directory** to `flutter_app`. This matters — the config files are not at the repo root.
3. Leave Framework Preset as **Other**. `vercel.json` supplies the build and install commands.
4. Add the environment variables in section 2, then deploy.

The Flutter SDK version is pinned deliberately in `install_flutter_vercel.sh`. An unpinned SDK means a Flutter
release can break production with no change on your side. When you upgrade Flutter locally, bump it there too.

## 2. Environment variables (Vercel → Project Settings → Environment Variables)

**Required** — the build fails fast with a clear message if either is missing:

| Variable | Value |
|---|---|
| `SUPABASE_URL` | `https://oxfnrsjskdjbroekxdco.supabase.co` |
| `SUPABASE_ANON_KEY` | your Supabase publishable/anon key |

**Optional** — absent simply means that feature stays off on web:

| Variable | Effect if omitted |
|---|---|
| `GOOGLE_WEB_CLIENT_ID` | Not required by the browser OAuth path; Google provider credentials belong in Supabase/Google Cloud |
| `GEMINI_API_KEY` | No live tutor calls or TTS. **See the security note before setting this.** |
| `OPENROUTER_API_KEY` | No LLM fallback |
| `SENTRY_DSN` | No crash reporting |
| `POSTHOG_API_KEY`, `POSTHOG_HOST` | No analytics |

Deliberately **not** used on web: `REVENUECAT_IOS_KEY` / `REVENUECAT_ANDROID_KEY` (no web IAP exists) and
`GOOGLE_IOS_CLIENT_ID` (native SDK only).

## 3. Supabase configuration

Google sign-in on web uses Supabase's OAuth redirect rather than the native SDK, so Supabase must know your
site. In **Authentication → URL Configuration**:

- **Site URL**: `https://app.your-domain.com` (your Vercel domain)
- **Redirect URLs**: add the same origin, plus `http://localhost:8734` if you want Google sign-in to work in
  local web dev.

The code passes `redirectTo: Uri.base.origin`, so the origin must be allow-listed or Supabase rejects the
round trip.

Also confirm **Authentication → Providers → Google** is enabled with your OAuth client ID and secret.

## 4. Google Cloud configuration

In **APIs & Services → Credentials**, on the **Web** OAuth 2.0 client ID:

- **Authorized JavaScript origins**: `https://app.your-domain.com`
- **Authorized redirect URIs**: `https://oxfnrsjskdjbroekxdco.supabase.co/auth/v1/callback`

The redirect URI points at Supabase, not at your app — Supabase brokers the exchange and then returns the user
to your origin.

## 5. Landing page link

Point the existing marketing site's Sign up / Log in button at the Vercel domain. Keep them as two separate
Vercel projects so a landing-page content change can never break the app build, and vice versa.

## 6. What works on web right now

- Email/password sign-up, sign-in, and password reset (pure Supabase, no platform-specific code).
- Google sign-in, once sections 2-4 are configured.
- Desktop app shell: sidebar navigation, top bar, Settings.
- Full lesson pipeline, SRS, competency graph, all labs and lessons — this is the same shared Dart code the
  iOS app runs, unchanged.
- Local database: Drift on SQLite compiled to wasm, persisted to IndexedDB. Verified end to end in a real
  browser (800 KB across 200 blocks written, migrations applied, content seeded).
- Live tutor call audio: a complete Web Audio implementation exists. Playback is verified; **mic capture is
  not yet verified on real hardware** — see below.

## 7. Known gaps

| Gap | Impact | Where it is tracked |
|---|---|---|
| Mic capture unverified on real hardware | Live calls may not work on web until checked | `05_phase5_voice_and_realtime.md` |
| No payments on web | Nobody can subscribe from the web app; RevenueCat is iOS/Android only | `03_phase3_auth_and_payments.md` |
| Apple sign-in hidden on web | Needs an Apple Service ID; Google and email cover it | `03_phase3_auth_and_payments.md` |
| Some interior screens still use mobile layouts | Sidebar/top bar and the first live lesson surfaces are desktop-shaped; remaining labs/interior pages still need their web pass | `07_web_ui_redesign.md` |
| No CI on web builds | A web-breaking change can reach production unnoticed | `06_phase6_deploy_and_hosting.md` |

Verify the mic before announcing web calls work:

```
flutter run -d chrome -t lib/dev/web_audio_check.dart
```

## Before public launch — read this

`--dart-define` values are **compiled into the JavaScript bundle** and readable by anyone who views source.

- `SUPABASE_ANON_KEY` is safe. It is designed to be public; row-level security is what protects your data.
- `GEMINI_API_KEY` and `OPENROUTER_API_KEY` are **not safe**. Anyone can extract them from the deployed bundle
  and spend your quota. On iOS the same defines sit inside a signed binary and are far less exposed; on the
  web they are effectively published.

This is acceptable for a private, internal, or invite-only deploy where you control who has the URL. It is not
acceptable for open public signup. The fix is to move those calls behind a Supabase edge function that holds
the key server-side, so the browser calls your function and never sees the key. That is a self-contained piece
of work and does not affect the iOS app.
