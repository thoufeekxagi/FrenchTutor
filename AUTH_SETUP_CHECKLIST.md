# Auth Setup Checklist — Google Cloud / Apple Developer / Supabase Dashboard

The sign-in screen, native Google/Apple/email flows, the `profiles` table with
RLS, the auto-provisioning trigger, and local-DB linking are in the app. Apple
sign-in is native. Email signup now returns to the iOS app after Supabase
confirms the address, provided the Supabase redirect allowlist and production
SMTP settings below are configured. Google sign-in shows a friendly "not
configured yet" message until its provider setup is complete, instead of
crashing.

These are the only things left, and every one of them requires clicking through
an external account (Google Cloud, Apple Developer, Supabase's own dashboard) —
nothing here can be done by a CLI or an MCP tool. Do them once, in this order.

---

## 1. Google Cloud Console — create the OAuth client IDs

Google's native sign-in needs **two** OAuth client IDs (this is a Google
requirement, not a design choice): one identifying the iOS app itself, one used
server-side by Supabase to verify the token's audience.

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → create a
   project (or pick an existing one) for ParleSprint.
2. **APIs & Services → OAuth consent screen**: choose External, fill in the app
   name ("ParleSprint") and your support email, save. Default scopes (email,
   profile) are enough — no need to add anything.
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - **Application type: iOS.** Bundle ID: `com.thoufeekx.frenchtutor`.
     After creating it, open the credential's details — Google shows both the
     **iOS Client ID** and its **reversed client ID** directly on that page.
     Copy both; you'll need the reversed one in step 3 below.
   - **Application type: Web application.** No redirect URIs are needed for
     this flow (we never redirect to it) — just create it and copy the
     **Web Client ID**.

4. Put both plain client IDs into `flutter_app/secrets.local.properties`:
   ```
   GOOGLE_IOS_CLIENT_ID=<the iOS client ID>
   GOOGLE_WEB_CLIENT_ID=<the Web client ID>
   ```

5. Put the **reversed** iOS client ID into
   `flutter_app/ios/Runner/Info.plist` — find the `CFBundleURLTypes` entry
   (there's an XML comment marking exactly this spot) and replace
   `com.googleusercontent.apps.REPLACE_WITH_REVERSED_IOS_CLIENT_ID` with the
   real reversed value Google showed you.

---

## 2. Supabase Dashboard — enable the Google and Apple providers

Go to the [ParleSprint project](https://supabase.com/dashboard/project/oxfnrsjskdjbroekxdco)
→ **Authentication → Providers**.

- **Google**: toggle on. In "Authorized Client IDs", paste BOTH the iOS and Web
  client IDs from step 1, comma-separated. (This is what lets Supabase accept
  ID tokens whose audience is either client.)
- **Apple**: toggle on. In "Authorized Client IDs" (sometimes labelled Bundle
  ID / Client ID), add: `com.thoufeekx.frenchtutor`.
- **Email**: already on by default — no action needed. "Confirm email" is on
  by default too; leave it on. The app uses this exact iOS confirmation
  callback; add it under **Authentication → URL Configuration → Additional
  Redirect URLs**:

  ```text
  com.thoufeekx.frenchtutor://auth-callback
  ```

  Set the Site URL to `https://parlesprint.com` and allowlist that web origin
  too. The callback is registered in `flutter_app/ios/Runner/Info.plist`;
  `supabase_flutter` handles the incoming link and session. The callback must
  be an exact allowlisted URL.

- **Production email delivery**: configure a custom SMTP server. Supabase's
  default sender is for development only: it restricts recipients to project
  team members and has a low sending limit. Resend can provide the SMTP
  transport; verify a sender domain first, then enter its SMTP credentials in
  Supabase **Authentication → SMTP Settings**. Put the Resend API key only in
  the Supabase SMTP password field (or another server-side secret store)—never
  in this repo, Flutter, or a `--dart-define`.
  This ParleSprint project is on the Free plan and was created after Supabase's
  June 3, 2026 change, so custom SMTP must be configured before its Auth email
  templates can be customized. See the
  [Supabase change](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier).

- **Confirmation template**: customize Supabase **Authentication → Email
  Templates → Confirm signup** with the wrapper link in
  [docs/auth-email-setup.md](docs/auth-email-setup.md), including its subject
  and preview text. The branded copy is prepared locally; it does not affect
  production sends until saved in the Supabase dashboard. The email opens a
  branded handoff page; the learner must tap its confirmation button before
  Supabase's one-time URL is consumed. Supabase still creates and verifies the
  token. Do not send a separate Resend email with a hand-built or guessed
  token. Disable Resend click tracking for this transactional email.

---

## 3. Xcode — sync the Apple Sign-In capability to your Developer account

The entitlement file (`Runner.entitlements`) and the Xcode project reference to
it are already committed. The one remaining step needs an Xcode GUI click
because it syncs the capability to your Apple Developer account, which no CLI
can do:

1. Open `flutter_app/ios/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target → **Signing & Capabilities** tab.
3. Click **+ Capability**, add **Sign in with Apple**.
4. With automatic signing (already configured, team `CF32XUVD59`), Xcode
   registers this capability on the App ID automatically — no separate
   developer.apple.com step needed.

---

## Known limitation to revisit later (not blocking)

**Password reset is not wired into the active sign-in screen yet.** Signup
confirmation now has the iOS callback. A future password-reset UI should use
the same registered callback and handle Supabase's recovery event before it is
exposed to learners.

**Android callback is a follow-up.** iOS is configured first. Before enabling
Android confirmation deep links, register a matching Android intent filter and
allowlist its callback URL in Supabase.

---

## After all of the above

Run `./bump_build_number.sh` then rebuild — Google sign-in will work exactly
like Apple and email already do: one tap, native picker, no browser, done.
