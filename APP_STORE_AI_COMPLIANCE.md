# Apple App Store Compliance for an AI Voice-Tutor App

Researched 2026-07-18 against Apple's current App Review Guidelines and recent policy
coverage. This is the single reference for what Apple actually requires from
ParleSprint given its shape: live voice AI (Gemini Live), text AI (Gemini Flash-Lite /
OpenRouter), a paid/free-tier model, and (once shipped) Supabase auth.

**Read this before the next TestFlight/App Store submission — not after.** Several of
these are the kind of thing that gets a first submission rejected outright, and fixing
them after users are already on an old data/privacy model is much more painful than
building them in from the start.

---

## The one finding that matters most: Guideline 5.1.2(i)

Apple added a guideline this cycle specifically targeting apps that send user data to
third-party AI services — which is exactly what every live call in this app does
(voice → Gemini Live; text → Gemini Flash-Lite / OpenRouter).

> **5.1.2(i) — Data Use and Sharing:** "You must clearly disclose where personal data
> will be shared with third parties, **including with third-party AI**, and obtain
> explicit permission before doing so."

What this means concretely, per Apple's guidance and current developer commentary:

- **On-device AI (Core ML, etc.) needs no special disclosure.** The moment data leaves
  the device to any external processor — even briefly, even just to generate a
  response — the rule is triggered. This unambiguously covers every Gemini/OpenRouter
  call this app makes.
- **Voice specifically is named**: "transmitting voice recordings or audio to external
  transcription or speech recognition services" is one of Apple's own example
  triggers. Every live call in ParleSprint does exactly this.
- The disclosure must **name the provider** (i.e., say "Google Gemini," not "AI
  services"), must be **explicit consent obtained before first transmission** — not
  buried in a general Terms of Service — and each category of sharing needs its own
  acknowledgment, not one bundled blanket consent.
- Practically, this needs: (1) a specific line item in the **App Privacy** nutrition
  label in App Store Connect (Audio Data → collected → linked to identity if signed
  in → used for App Functionality, shared with a third party), (2) a real, published
  **privacy policy URL** that names Google (Gemini) and OpenRouter as processors of
  voice/text data, and (3) an **in-app consent moment** — realistically, a screen the
  first time a user starts a live call: "Your voice is sent to Google's Gemini AI to
  power your tutor. [Learn more] [Continue]" — before the mic ever opens.

**Action item:** build this consent screen and the privacy policy page before first
submission. It's a small, contained piece of work and it's the one item most likely
to cause an outright rejection if skipped.

---

## Guideline 1.2 / 4.7 — content moderation ("is this a chatbot app?")

The guidelines' explicit "chatbot" language (4.7) is actually written for a different
scenario than ours — third-party mini-programs a *super-app* hosts and distributes
inside itself (Apple's example is more WeChat-style than "my app has an AI feature").
ParleSprint's tutor personas are the app's own first-party feature, not a hosted
third-party bot marketplace, so 4.7's letter doesn't strictly apply.

That said, Guideline **1.2 (User-Generated Content / Safety)** and Apple's general
review posture in 2026 both push toward the same practical bar regardless of which
guideline number technically fires: any app where a user can produce or receive
freeform generated content needs, in spirit:

- A method for filtering objectionable material.
- A way to report a problem and a channel that gets a timely response.
- A way to end/block a bad interaction.
- Published contact info.

**Where this app already stands:** the `contentSafety` prompt block (shipped in P0)
already instructs the tutor to never produce or engage with offensive content, in any
language. That's the generation-side half. What's still missing for review purposes:
a simple **in-call "Report a problem" affordance** and a **support/contact email
visible in the app** (Settings already shows `thoufeek@agiventures.ca` — good, keep
it prominent). No user-to-user content exists in this app (it's user↔AI only), which
meaningfully lowers the bar versus a social/UGC app, but "AI said something
inappropriate, here's how to flag it" is worth having before submission regardless.

---

## Age rating

Apple's 2025–2026 rating overhaul added 13+/16+/18+ tiers alongside the old 4+/9+/12+,
with a **compliance deadline of January 31, 2026 — already passed** as of this
writing. If the age rating in App Store Connect hasn't been re-answered under the new
questionnaire yet, that's an outstanding item independent of anything AI-related.

Apple's current guidance explicitly calls out AI: because generated dialogue is
inherently less predictable than authored content, apps with AI chat/conversation
features are pushed toward acknowledging that in the age-rating questionnaire (the
"Mature/Suggestive Themes" and "Unmoderated User-to-User Communication" style
questions now have AI-aware framing). **Realistic expectation for this app: 12+ or
13+**, not 4+, precisely because a live AI conversation cannot be 100% content-guaranteed
even with the `contentSafety` prompt block in place. Rating honestly here (2.3.6)
matters more than rating low — a mis-rated app risks the guideline violation Apple
explicitly warns about ("customers might be surprised... or it could trigger an
inquiry from government regulators").

**Action item:** answer the current-format age-rating questionnaire in App Store
Connect acknowledging AI-generated conversational content; expect and accept a 12+/13+
result rather than fighting for 4+.

---

## Subscriptions / the free-hour model (Guideline 3.1.x)

Directly relevant to the planned "1 free hour, then paid" model:

- **Any unlock of paid features/content must go through Apple's In-App Purchase**,
  not a custom paywall billed outside Apple's system (3.1.1). This includes a
  subscription for continued daily tutor access after the free hour.
- Auto-renewable subscriptions must provide **ongoing value** and run **≥7 days**
  minimum (3.1.2(a)) — a monthly plan is the natural fit; anything shorter than a
  week isn't allowed as a subscription.
- Before the paywall appears, the app must **clearly state what's included, the
  price, and the renewal terms** (3.1.2(c)) — a simple, honest paywall screen
  satisfies this; nothing exotic needed.
- If offering a free trial via a non-subscription unlock, the trial's duration and
  what stops working afterward must be stated **before** the trial starts (3.1.2(a)).
  Simplest path for this app: the "1 free hour" IS the trial — frame it exactly that
  way in the UI ("Your first hour with a tutor is free — here's what happens after"),
  and this requirement is satisfied by being upfront about it, which the product
  already intends to do.

**Action item:** when P1.2 (rate limits) is built, the paywall/upgrade screen must
route through StoreKit/In-App Purchase, not a custom Stripe-style checkout — this is
a hard Apple rule, not a style preference.

---

## Encryption export compliance

Every network call this app makes is a normal HTTPS/TLS request (Gemini API,
OpenRouter, Supabase) — this is the **exempt** category. In Xcode's export compliance
question ("Does your app use encryption?"), the correct answer for this app is: uses
encryption, but only exempt forms (standard HTTPS/TLS) → `ITSAppUsesNonExemptEncryption
= NO` in Info.plist. No special export documentation is needed unless a custom
cryptographic algorithm is ever added (it isn't).

---

## What Supabase changes here, and what it doesn't

Two genuinely different things are being conflated in "connect Supabase" — worth
separating clearly:

1. **Auth** (P1.1 in the pilot plan) — Sign in with Apple via Supabase Auth. If this
   app *only* offers Sign in with Apple (no Google/Facebook/etc. login), Guideline
   **4.8** (which requires offering Apple Sign-In whenever another third-party login
   is offered) never triggers — there's no "another" login to trigger it. Keep it
   simple: Apple-only sign-in avoids an entire extra guideline.
2. **Secret-proxying** (moving the Gemini/OpenRouter API keys behind a Supabase Edge
   Function instead of compiling them into the client binary). This is **not** an
   Apple guideline requirement — Apple's review process doesn't decompile binaries
   looking for embedded secrets. It is, however, a **real, independent security
   problem worth fixing anyway**: Flutter's `--dart-define` values are compiled as
   plain strings into the release binary and are trivially extractable with basic
   reverse-engineering tools (`strings` on the compiled snapshot, or a decompiler).
   Once this app is on the App Store, anyone can pull the IPA and extract the raw
   Gemini/OpenRouter keys, then use them for free, potentially exhausting quota or
   violating Google's ToS in your name. This matters *more*, not less, once real
   money/usage limits are involved (P1.2's free-hour wallet is meaningless if the
   underlying key is public).

**How the proxy should work, concretely:**
- A Supabase Edge Function (Deno, runs on Supabase's servers) holds the real Gemini
  API key as a server-side secret (`supabase secrets set GEMINI_API_KEY=...` — never
  in client code, never in git).
- The Flutter app authenticates the user via Supabase Auth, then calls the Edge
  Function with the user's Supabase session token instead of a raw Gemini key.
- The Edge Function verifies the token, checks the user's remaining free-hour balance
  (a real server-side check — this is what makes rate-limiting actually enforceable,
  not just a client-side number that a jailbroken/reinstalled app can ignore), then
  either proxies the request to Gemini or opens/relays a WebSocket for the Live API
  and returns the result.
- The client's only secret becomes the Supabase **anon/public key**, which is
  *designed* to be public (it's meaningless without Row Level Security policies
  gating what it can actually read/write) — nothing sensitive ships in the binary
  anymore.
- Live audio calls (Gemini Live's WebSocket) are the one part worth thinking through
  specifically: Supabase Edge Functions can proxy WebSocket connections, but it adds
  a hop of latency to every live call. An alternative that avoids that: have the Edge
  Function mint a **short-lived, scoped Gemini token** (ephemeral token) that the
  client uses to connect directly to Gemini for that one call only — the real
  long-lived key never leaves the server, and there's no added latency on the audio
  path. Gemini's Live API supports ephemeral tokens for exactly this use case. This is
  the better design for the voice path specifically; the plain proxy pattern is fine
  for the text-brain calls (grading, planning, intent judging).

**What Supabase does NOT need to solve before submission:** the full bidirectional
local↔cloud sync layer, RLS on every content table, multi-device sync. Those are
genuinely post-launch concerns — local SQLite stays the source of truth for lesson
content and progress either way. Don't block shipping on building all of that.

---

## Direct answer: sequencing — Supabase-first, or app-first?

**Neither extreme. Do the minimal Supabase slice first, defer the rest.**

Do **before** any TestFlight/App Store submission:
1. Supabase Auth wired (Apple Sign-In only — simplest, avoids Guideline 4.8 entirely).
2. Gemini/OpenRouter keys moved behind a Supabase Edge Function (ephemeral tokens for
   the Live voice path, plain proxy for text calls) — kills the embedded-secret risk
   and makes the free-hour wallet actually enforceable server-side.
3. A real, published privacy policy page naming Google/Gemini and OpenRouter as
   third-party AI processors, plus the App Privacy nutrition label filled in to
   match.
4. A first-run consent screen before the first live call ever opens the mic — this is
   what actually satisfies 5.1.2(i), not just the privacy policy existing somewhere.
5. Age rating answered honestly under the new 2026 questionnaire (expect 12+/13+).
6. A minimal in-call "report a problem" affordance + visible support contact.

Defer to **after** first submission / initial pilot feedback:
- Full local↔Supabase bidirectional sync of lesson content/progress across devices.
- RLS policies on every future content table (only the auth-adjacent tables need them
  now — user profile, usage ledger).
- Multi-provider login (Google/Facebook) — every provider added *after* Apple Sign-In
  is free of Guideline 4.8 concern since Apple Sign-In is already offered.

**Why this order, not "ship first, add Supabase later":** the privacy nutrition label
and the age rating are answered *at submission time* — changing the underlying data
flow afterward (adding accounts, changing who processes what) means updating those
disclosures and effectively re-litigating this exact question during a later review,
under more time pressure, with real users already depending on the old behavior. It's
cheaper to get the disclosure/consent/key-security slice right once, now, than to
patch it retroactively after a rejection or after shipping something that has to
change under existing users.

**Why not the full Supabase migration first either:** the complete sync/RLS/
multi-table architecture doesn't block review or security — it's an engineering
completeness question, not a compliance one. Building all of it before ever getting
the app in front of a real reviewer or a real tester risks polishing architecture
nobody has validated against actual App Store review feedback yet.

---

## Concrete next build order (once you say go)

1. Supabase Auth (Sign in with Apple) wired into the Flutter app, local rows adopt
   the new `user_id` on first login — exactly as scoped in `PILOT_PLAN.md` Phase 5,
   just moved earlier in sequence per the reasoning above.
2. Edge Function(s): one for text-brain proxying, one issuing ephemeral Gemini Live
   tokens for the voice path. Server-side usage ledger lives here too — this is the
   same infrastructure P1.2 (rate limits) already needed, just built now instead of
   later.
3. Privacy policy page + App Privacy nutrition label + first-run AI-disclosure
   consent screen.
4. Age rating re-answered honestly in App Store Connect.
5. First TestFlight build, keys never touching the client.

Sources:
- [App Review Guidelines - Apple Developer](https://developer.apple.com/app-store/review/guidelines/)
- [Apple Silently Regulated Third-Party AI — Guideline 5.1.2(i)](https://dev.to/arshtechpro/apples-guideline-512i-the-ai-data-sharing-rule-that-will-impact-every-ios-developer-1b0p)
- [Updated App Review Guidelines now available - Apple Developer News](https://developer.apple.com/news/?id=d75yllv4)
- [App Store Guidelines Explained](https://www.debutinfotech.com/blog/apple-app-store-guidelines)
- [How to Resolve App Store Guideline 1.2 - BuddyBoss](https://buddyboss.com/docs/app-store-guideline-1-2-safety-user-generated-content/)
- [Apple App Store Review Guideline 1.2 Explained - AcceptMyApp](https://acceptmy.app/guidelines/1-2-user-generated-content)
- [Overview of export compliance - Apple Developer](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [ITSAppUsesNonExemptEncryption - Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/itsencryptionexportcompliancecode)
- [App Privacy Details - Apple Developer](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple clamps down on third-party AI data sharing - TechBuzz](https://www.techbuzz.ai/articles/apple-clamps-down-on-third-party-ai-data-sharing-in-app-store)
- [Age ratings values and definitions - App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Updated age ratings in App Store Connect - Apple Developer News](https://developer.apple.com/news/?id=ks775ehf)
