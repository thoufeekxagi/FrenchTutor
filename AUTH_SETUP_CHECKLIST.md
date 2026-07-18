# Auth Setup Checklist — Google Cloud / Apple Developer / Supabase Dashboard

Everything code-side is already built and committed: the sign-in screen, native
Google/Apple/email flows, the `profiles` table with RLS, the auto-provisioning
trigger, and local-DB linking. **The app builds and runs right now** — Apple
sign-in and email/password already work with zero further setup. Google sign-in
shows a friendly "not configured yet" message until the steps below are done,
instead of crashing.

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
  by default too; leave it on (the app already handles the
  "check your email to confirm" state correctly either way).

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

**Password reset email links open a web page, not the app.** `resetPasswordForEmail`
sends a real, working reset link — but without deep-linking configured (Universal
Links / associated domains), that link opens in a browser rather than jumping back
into ParleSprint. Functional today, just not the smoothest possible hop. Worth
fixing once the app has an established URL scheme for deep links generally —
not worth blocking the rest of auth on.

---

## After all of the above

Run `./bump_build_number.sh` then rebuild — Google sign-in will work exactly
like Apple and email already do: one tap, native picker, no browser, done.
