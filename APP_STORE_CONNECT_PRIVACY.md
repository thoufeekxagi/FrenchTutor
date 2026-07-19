# App Store Connect submission packet

Everything you need to have open in front of you while filling in App Store Connect.
Nothing here needs research at submission time — it's all decided now, while the
details are fresh. Companion to `APP_STORE_AI_COMPLIANCE.md` (the "why," researched
2026-07-18) — this is the "what to actually type into each field."

---

## 1. Reviewer demo account

App Review needs to sign in without a real Apple/Google account. Give them this,
verbatim, in the **App Review Information → Sign-In Information** section:

- **Email:** `admin@parlesprint.com`
- **Password:** `admin`
- **Sign-in method:** Email/password (the "Sign in with email" option on the auth screen — Apple/Google sign-in buttons are also present but this account doesn't need them)

This account is flagged server-side (`profiles.reviewer_account = true` in Supabase)
to skip the normal 60-minutes/day speaking cap, so review can't get blocked mid-session
by hitting a limit. It's a permanent account — don't delete it, and don't "clean it up"
after approval; Apple re-reviews every update using the same credentials unless you
change them in App Store Connect first.

---

## 2. Review Notes (paste into App Review Information → Notes)

```
ParleSprint is an AI-powered French speaking/listening tutor. A few things that help
review go smoothly:

1. AI provider: live voice conversations use Google's Gemini Live API (audio in,
   audio out) and text practice uses Google Gemini (with an optional OpenRouter
   fallback a user can configure themselves). The first time any account starts a
   live voice call, the app shows an explicit consent screen naming Google Gemini
   before the microphone opens (Settings → the app never records without this
   screen being accepted first).

2. Sign-in: demo account above. Real users can also sign in with Apple, Google, or
   email/password — Apple Sign-In is offered whenever any other third-party login is
   offered.

3. Account deletion: Settings → Account → "Delete account" permanently deletes the
   Supabase auth account and all local data, no separate request needed.

4. Reporting AI content: every live call screen has a flag icon ("Report a problem")
   that opens a pre-filled email to our support address for anything the AI tutor
   says that's wrong or inappropriate.

5. Privacy policy: https://parlesprint.com/privacy — names Google Gemini and
   OpenRouter explicitly as data processors, explains local + Supabase storage, and
   describes deletion rights.

Happy to answer anything else at thoufeek@agiventures.ca.
```

(Fill in the actual privacy policy URL once it's pushed — see §6.)

---

## 3. App Privacy questionnaire (the "nutrition label")

Go to **App Store Connect → App Privacy → Get Started**. Answer per data type below.
Anything not listed here → answer "No, we do not collect this data."

| Data type | Collected? | Linked to identity? | Used for tracking? | Purpose(s) |
|---|---|---|---|---|
| **Email Address** | Yes | Yes | No | App Functionality (account/sign-in) |
| **Name** | Yes (if user shares it via Apple/Google sign-in) | Yes | No | App Functionality |
| **User ID** | Yes | Yes | No | App Functionality |
| **Audio Data** | Yes (voice practice, streamed to Gemini Live) | Yes | No | App Functionality (tutoring), Product Personalization |
| **Other User Content** | Yes (text chat, practice answers, transcripts) | Yes | No | App Functionality, Product Personalization |
| **Product Interaction** | Yes (lesson/vocab/session progress) | Yes | No | App Functionality, Product Personalization, Analytics (internal only, not shared) |
| **Other Usage Data** | Yes (streaks, completion state) | Yes | No | App Functionality, Product Personalization |
| **Precise/Coarse Location** | No | — | — | — |
| **Contacts** | No | — | — | — |
| **Photos or Videos** | No | — | — | — |
| **Search History** | No | — | — | — |
| **Browsing History** | No | — | — | — |
| **Health & Fitness** | No | — | — | — |
| **Financial Info** | No (subscriptions go through Apple/Google IAP, not handled by us directly) | — | — | — |
| **Advertising Data** | No | — | — | — |
| **Diagnostics/Crash Data** | No (no analytics/crash SDK currently integrated) | — | — | — |

**Tracking question ("Do you or your third-party partners use data collected from
this app to track users?")** → **No.** Nothing here is used across other companies'
apps/websites for ads, and there's no ad SDK.

**Third-party data sharing** — when App Store Connect asks "is this data shared with
a third party," answer **Yes** for Audio Data, Other User Content, and Product
Interaction, and name:
- **Google (Gemini API / Gemini Live API)** — receives audio + text to generate tutor
  responses and grading.
- **OpenRouter** — same categories, only if a user opts into configuring it.
- **Supabase** — infrastructure processor (auth + database), not a third party the
  data is "shared with" for their own purposes — it's your own backend.

---

## 4. Age rating

Answer the 2026-format questionnaire honestly. Given live, not-fully-moderated AI
conversation, expect and accept **12+ or 13+** — do not try to force 4+. Apple's own
guidance (2.3.6) treats an honest higher rating as safer than a mis-rated low one.
There's no code change needed here, just an honest answer in App Store Connect.

---

## 5. Encryption / export compliance

`ITSAppUsesNonExemptEncryption = false` is already set in `ios/Runner/Info.plist` —
Xcode/App Store Connect should not prompt for this at upload, but if it does, the
answer is: **uses encryption, exempt (standard HTTPS/TLS only)**.

---

## 6. Before you actually hit Submit

- [ ] Push `ParleSprintWebsite` so `parlesprint.com/privacy` and `/terms` are live —
      the Privacy Policy URL field in App Store Connect needs a real, reachable page.
- [ ] Fill in §3 above in App Store Connect's App Privacy section.
- [ ] Paste §2 into App Review Information → Notes.
- [ ] Enter the §1 demo credentials into Sign-In Information.
- [ ] Answer the age rating questionnaire (§4).
- [ ] Run the crash/edge-case QA pass (see the separate QA checklist — kept outside
      this repo) on a real device before uploading the build.
- [ ] Double-check screenshots match the current app exactly — mismatched
      screenshots are one of the most common rejection reasons independent of
      anything privacy-related.
