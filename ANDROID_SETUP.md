# Android Setup — Build, Emulator, and Sign-In

Companion to `BUILD_FLUTTER_TO_IPHONE.md` (iOS) and `AUTH_SETUP_CHECKLIST.md`
(OAuth setup). This covers everything specific to getting the app building and
running on Android, including the exact problems hit while setting this up on
a fresh machine, so the next person doesn't have to rediscover them.

---

## 1. Toolchain requirements

The project pins fairly current tooling. If `flutter pub get` fails with a
Dart SDK version error, your Flutter install is too old — run `flutter
upgrade` (needs Flutter **3.44.8+**, which ships Dart **3.12.2+**, matching
`environment: sdk: ^3.12.2` in `pubspec.yaml`).

Everything else is already declared in the repo and gets installed
automatically by Gradle/the Android SDK manager on first build:

- Gradle 9.1.0 (`flutter_app/android/gradle/wrapper/gradle-wrapper.properties`)
- Android Gradle Plugin 9.0.1 + Kotlin 2.3.20 (`flutter_app/android/settings.gradle.kts`)
- NDK 28.2.13676358, Android SDK Build-Tools 36 — auto-installed on first
  `flutter build apk`, accepting the license prompt if asked
- Java 17 (the JDK Flutter's own tool bundles, or any JDK 17 on `PATH`)

Run `flutter doctor -v` first — you want a green checkmark on "Android
toolchain." If Android Studio isn't installed, that's fine; it's **not
required**. The Android SDK + command-line tools + emulator are sufficient on
their own, which is what this whole setup uses.

### Known build-breaking issue already fixed on this branch

`sentry_flutter` versions before 9.x hardcode a Kotlin `languageVersion`
setting in their bundled Android `build.gradle` that Kotlin 2.3.20 (required
by AGP 9) no longer accepts, causing `assembleDebug` to fail with a Kotlin
compiler error on `:sentry_flutter:compileDebugKotlin`. This branch bumps
`sentry_flutter` to `^9.26.0`, which removed that setting. If you see this
again on some other plugin down the line, the fix is the same: check whether
a newer release of that plugin dropped its own hardcoded Kotlin config —
Flutter plugins that still apply their own Kotlin Gradle Plugin (rather than
"Built-in Kotlin") are a known, ongoing AGP 9 migration pain point across the
whole plugin ecosystem, not something specific to this app.

---

## 2. Secrets

Copy the template and fill in real values:

```bash
cd flutter_app
cp secrets.local.properties.example secrets.local.properties
```

Real values for the shared "ParleSprint" project (Supabase URL, anon key,
Gemini, OpenRouter, Sentry, PostHog, Google OAuth client IDs) are passed
around outside of git — ask whoever's coordinating for the current `.env`
file (or the previous developer's `secrets.local.properties`) rather than
recreating each service from scratch. Nothing in this file is safe to commit;
it's already gitignored.

Run via the existing helper scripts (`run_with_keys.sh` /
`run_release_with_keys.sh`), or pass the same values as `--dart-define` flags
directly to `flutter build apk` / `flutter run` if those scripts' hardcoded
device targets don't fit your setup — the scripts were written assuming a
physical iOS device over USB, so on Linux/Android you'll likely invoke
`flutter build apk` yourself with the same `--dart-define` list rather than
using the script verbatim.

---

## 3. Emulator setup (lightweight, no Play Store bloat)

Create an AVD using a plain `google_apis` (not `google_apis_playstore`)
x86_64 image — this has Google Play Services (needed for Google Sign-In) but
skips the Play Store app itself, keeping it lightweight:

```bash
sdkmanager --install "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n my_test_avd -k "system-images;android-34;google_apis;x86_64" -d pixel_6
```

### The one real gotcha: boot with `-no-snapshot`

On first boot, this specific system image can hit a real (documented, not
machine-specific) init bug — SELinux denies `toybox_vendor` execution while
setting up `/data/misc`'s encryption policy, which makes Android's `init`
process reboot into recovery, which then also fails because the AVD has no
`/misc` partition. The symptom: the emulator appears to hang indefinitely (or
for a very long time) with `adb devices` stuck showing `offline`, and the
last visible log line is `Activated packet streamer for bluetooth emulation`.

**Fix:** always boot with `-no-snapshot` (bypasses a snapshot-loading path
that makes the failure much worse) alongside a normal cold start:

```bash
emulator -avd my_test_avd -no-snapshot -gpu swiftshader_indirect -no-audio
```

If you hit the hang anyway on first-ever boot, add `-wipe-data` once to force
a truly clean disk, then drop it for all subsequent boots. Once it's booted
successfully one time, plain `emulator -avd my_test_avd` (letting it use its
saved snapshot) boots in seconds from then on.

If you have a discrete GPU (NVIDIA on a hybrid/Optimus laptop, for example),
drop `-gpu swiftshader_indirect` in favor of real acceleration:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
  emulator -avd my_test_avd -no-snapshot -gpu host -no-audio
```

(Remove `-no-audio` if you actually want to hear TTS/audio previews play
through your speakers — needed for anything in the alphabet/liaison labs or
tutor voice previews.)

### Installing and running

```bash
flutter build apk --debug --dart-define=... (see secrets section above)
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.thoufeekx.french_tutor/.MainActivity
```

---

## 4. Google Sign-In on Android

The repo's `AUTH_SETUP_CHECKLIST.md` only documents the **iOS** OAuth client
setup. Android needs one more, separate piece in the same Google Cloud
project: an **Android-type** OAuth client, matched by package name + signing
certificate fingerprint (not a client ID passed into the app — the app keeps
using `GOOGLE_WEB_CLIENT_ID` for both platforms; Android's client only needs
to exist in Google's records for the native picker to stop returning
`ApiException: 10` / `DEVELOPER_ERROR`).

1. Get your machine's debug keystore SHA-1 (every machine's auto-generated
   debug keystore is different, so this fingerprint is yours, not something
   to copy from someone else):
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA1
   ```
2. Google Cloud Console → **APIs & Services → Credentials → Create
   Credentials → OAuth client ID** → type **Android**
3. Package name: `com.thoufeekx.french_tutor`, SHA-1: (from step 1)
4. Create — no further wiring needed, the client just needs to exist

**Team note:** each developer's debug keystore SHA-1 is different unless you
deliberately share one `debug.keystore` file across the team. Either every
developer registers their own Android OAuth client entry (simplest — multiple
Android-type clients can coexist in the same project, one per teammate), or
the team standardizes on a single shared debug keystore file distributed
out-of-band. When the app eventually gets published, Google Play App Signing
generates yet another, different release certificate — that SHA-1 needs its
own additional Android OAuth client entry in the same project at that point.

Apple Sign-In does **not** currently work on Android — tapping it throws
`Exception: 'webAuthenticationOptions' argument must be provided on
Android`, a real gap in the `sign_in_with_apple` wiring for Android's
web-based fallback flow (Apple's native picker is iOS-only by design; Android
requires routing through a web OAuth flow that isn't configured yet). Email/
password and Google both work end-to-end on Android as of this branch.
