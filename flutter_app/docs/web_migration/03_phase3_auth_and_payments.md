# Phase 3: Auth & Payments for Web

**Status**: **Auth done for web. Payments NOT started.**

Auth, done:
- Email/password sign-up, sign-in, and password reset already worked on web with zero changes — they are pure
  Supabase calls. This is what makes the web app deployable today.
- Google sign-in now works on web via Supabase's OAuth redirect (`signInWithOAuth`, `redirectTo:
  Uri.base.origin`). Native keeps its existing no-browser `signInWithIdToken` account-picker flow, untouched.
  The branch lives inside `AuthService` itself, which IS the leaf seam for "trigger a sign-in", rather than
  being pushed up into any screen. Needs the console config in `DEPLOY_WEB.md` sections 3-4.
- `isGoogleConfigured` no longer blocks web OAuth on a Google client ID. Supabase owns the provider configuration; the browser only needs the OAuth redirect path.
- Apple sign-in is **hidden on web** (`AuthService.isAppleAvailable`) because it needs an Apple Developer
  Service ID and registered return URL we have not set up. Showing a button that always fails is worse than
  not showing it. Native is unaffected. Decision still open on whether web ever gets Apple sign-in.

Payments, not started: RevenueCat is iOS/Android only, so **no entitlement path exists on web at all**. Nobody
can subscribe from the web app. The Stripe vs RevenueCat Web Billing decision below is still unmade.

## Auth

Supabase (`supabase_flutter`) already works on web. What differs is *how sign-in is triggered*:

- **iOS/Android today**: native Google Sign-In SDK and native Sign In with Apple SDK, both funneled into a
  Supabase session (per the existing "Native Google/Apple/email auth via Supabase — no browser redirect,
  ever" design decision for mobile).
- **Web**: no native SDK sheet exists. Use Supabase's web OAuth flow (redirect to Google/Apple's OAuth page,
  redirect back with a session). This is a standard, well-documented Supabase Flutter Web pattern.

**Recommended approach**: define (or locate, if it already exists) an `AuthService` interface with one method
per sign-in method (`signInWithGoogle()`, `signInWithApple()`, `signInWithEmail()`). Keep the existing native
implementation for iOS/Android untouched. Add a web implementation that calls Supabase's OAuth redirect flow
instead. Conditional-import selects the right one; every screen that currently calls the native sign-in
functions keeps calling the same interface method, unaware of which implementation is active.

**Open decision**: is Apple Sign-In worth supporting on web at all for v1? Web users are less likely to be on
Safari/Apple ecosystem than iOS users; Google + email/password may cover web adequately for launch, with Apple
sign-in added later if data shows it's needed. Decide before implementing, not after — don't build a web Apple
sign-in flow speculatively if it won't be used.

## Payments

RevenueCat's IAP model doesn't exist on web — there is no App Store/Play Store billing sheet in a browser.

**Options**:
1. **Stripe** (Checkout or Payment Element) as a separate web billing backend, with your own webhook writing
   entitlement state into the same Supabase tables the app already reads for subscription gating.
2. **RevenueCat Web Billing** — RevenueCat has a web billing product that can write into the same RevenueCat
   customer record used by iOS/Android, which would keep entitlement logic unified across all three platforms
   in one vendor. Worth evaluating first since it avoids maintaining two separate entitlement systems, but
   confirm current feature parity/pricing before committing.

**Recommended approach regardless of vendor choice**: `subscription_gate_service.dart` (or wherever entitlement
checks live) should read from ONE unified "is this user entitled" call that doesn't care which vendor granted
it. Web-specific checkout UI is new code; the gating logic that every screen already calls stays unchanged.

## Deliverable

- Decision recorded here: Stripe vs RevenueCat Web Billing, and whether web ships with Apple Sign-In at
  launch.
- `AuthService` interface (or equivalent) with iOS/Android and web implementations, both passing existing auth
  tests plus new web-specific tests.
- Web checkout flow wired into the same entitlement-check interface the rest of the app already uses.
