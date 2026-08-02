# Android Setup — Build, Emulator, and Sign-In

Companion to `BUILD_FLUTTER_TO_IPHONE.md` (iOS) and `AUTH_SETUP_CHECKLIST.md`
(OAuth setup). This covers everything specific to getting the app building and
running on Android, including the exact problems hit while setting this up on
a fresh machine, so the next person doesn't have to rediscover them.

**Before doing anything else on a new machine, run:**
```bash
cd flutter_app && ./android_preflight_check.sh
```
It's read-only — checks Flutter/Dart version, the Android toolchain, and
scans every installed plugin for the exact Kotlin-incompatibility bug class
that broke this project's build once already (section 1 below), so you find
out in 10 seconds instead of after a failed 15-minute Gradle build.

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

## 3. Emulator setup (lightweight, no Play Store bloat, works on Windows/macOS/Linux)

The whole point of this section: pick the newest stable image and the right
acceleration for your OS *up front*, so you never end up debugging a stale,
under-accelerated emulator the way this branch's setup originally did. Don't
copy a hardcoded API-level number from an old doc (including an older version
of this one) without checking it's still current — Android API levels move
fast and pinning to whatever was "latest" months ago is exactly how you end
up on old, more bug-prone system images.

### Step 0 — find your SDK tools (OS-specific paths)

| OS | Default SDK location | `sdkmanager` / `avdmanager` / `emulator` live in |
|---|---|---|
| Linux | `~/Android` or `~/Android/Sdk` | `cmdline-tools/latest/bin/`, `emulator/` |
| macOS | `~/Library/Android/sdk` | same subfolders |
| Windows | `%LOCALAPPDATA%\Android\Sdk` | same subfolders (`.bat` scripts instead of extension-less) |

If you already installed Android Studio at any point, it created this for
you. If not, download just the **command-line tools** package from
[developer.android.com/studio](https://developer.android.com/studio) —
scroll to "Command line tools only" — you do **not** need the full Android
Studio IDE to build or run this app; everything in this doc is pure CLI.

### Step 1 — install the newest stable system image (not Play Store)

List what's actually available right now rather than trusting any hardcoded
version number:

```bash
sdkmanager --list | grep "system-images.*google_apis;"
```

Pick the **highest-numbered stable API level** (skip anything with a
pre-release/preview tag) with tag `google_apis` — not `google_apis_playstore`
(that variant bundles the full Play Store app, which is unnecessary weight
for local testing and slower to boot). Match the ABI to your machine:
`x86_64` for Intel/AMD, `arm64-v8a` for Apple Silicon Macs.

```bash
sdkmanager --install "system-images;android-<HIGHEST_STABLE>;google_apis;<ABI>"
avdmanager create avd -n my_test_avd -k "system-images;android-<HIGHEST_STABLE>;google_apis;<ABI>" -d pixel_6
```

Also make sure the emulator engine itself is current (this is separate from
the system image and updates independently):

```bash
sdkmanager --update
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

### Hardware acceleration (matters a lot for boot speed — don't skip this)

Without it, boots take minutes instead of seconds. What "on" looks like
differs per OS:

- **Linux**: needs `/dev/kvm` to exist and your user in the `kvm` group
  (`groups` should list it; if not, `sudo usermod -aG kvm $USER` then log out
  and back in). Verify with `emulator -accel-check` — it should say "KVM ...
  is installed and usable." If you have a discrete GPU on a hybrid laptop
  (NVIDIA Optimus, for example), route the emulator's rendering to it instead
  of the integrated GPU:
  ```bash
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    emulator -avd my_test_avd -no-snapshot -gpu host -no-audio
  ```
  Otherwise, plain software rendering is still far better than nothing:
  ```bash
  emulator -avd my_test_avd -no-snapshot -gpu swiftshader_indirect -no-audio
  ```
- **macOS**: hardware acceleration (Apple's Hypervisor.Framework) is used
  automatically — nothing to configure. Just run
  `emulator -avd my_test_avd -no-snapshot -gpu auto -no-audio`. Apple
  Silicon Macs need an `arm64-v8a` system image (see Step 1); Intel Macs need
  `x86_64`.
- **Windows**: acceleration comes from either Windows Hypervisor Platform
  (WHPX, the modern default — make sure it's enabled in "Turn Windows
  features on or off") or the older Intel HAXM on machines that don't support
  WHPX. `emulator -accel-check` tells you which one is active. Same command
  otherwise: `emulator -avd my_test_avd -no-snapshot -gpu auto -no-audio`.

(Drop `-no-audio` on any OS if you actually want to hear TTS/audio previews
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

---

## 5. Full troubleshooting log from setting this up the first time

Kept in detail on purpose — several of these looked like different bugs
before turning out to be the same root cause, or looked like real bugs and
turned out to be nothing. Recognizing the *symptom* quickly is the whole
value of this section.

**Symptom: `flutter pub get` fails with a Dart SDK version error.**
Your Flutter is older than this project's `environment: sdk:` constraint.
`flutter upgrade`. Not a project bug.

**Symptom: `assembleDebug`/`assembleRelease` fails on
`:sentry_flutter:compileDebugKotlin` with `Language version 1.6 is no longer
supported`.** Covered in section 1 — already fixed on this branch by bumping
`sentry_flutter`. If a *different* plugin throws the same shape of error
later, `android_preflight_check.sh` section 4 is built to catch it — run it
against the new plugin's cached `android/build.gradle`.

**Symptom: emulator boots forever, `adb devices` stuck on `offline`, log
frozen at `Activated packet streamer for bluetooth emulation`.** This is the
init/SELinux bug from section 3 — fix is `-no-snapshot` (and `-wipe-data`
once if it's a truly fresh AVD). Do **not** chase this as a disk-speed or
RAM problem — that was a real dead end the first time this was diagnosed:
several minutes were spent checking `vmstat` I/O-wait and killing IDE/build
processes to "free up resources," which helped a little (any real resource
contention on a busy machine will genuinely slow *any* boot down) but was
not the actual root cause. The actual fix that made it boot in ~10 seconds
was `-no-snapshot`, nothing about RAM or disk.

**Symptom: `-no-window` (headless) hangs at the exact same
"packet streamer" line, but a windowed boot of the identical AVD eventually
gets further.** Headless mode has its own separate, documented flakiness on
some Linux setups unrelated to the init bug above. If you need headless
(CI, no display), test that specifically rather than assuming it behaves
like windowed mode.

**Symptom: Google Sign-In shows `PlatformException(sign_in_failed,
ApiException: 10, ...)` after picking an account.** `ApiException: 10` is
Google's own `DEVELOPER_ERROR` — it means no Android-type OAuth client is
registered for this app's package name + SHA-1 combination yet. Section 4
above is the fix. It is **not** fixed by adding a Google account to the
emulator, and it is **not** fixed by the Web OAuth client that iOS/Supabase
already use — Android needs its own, additional client registration, purely
for Google's own bookkeeping (no ID from it is ever used in app code).

**Symptom: a shell script using `set -euo pipefail` reports a check as
failed even though the underlying command clearly succeeded (e.g. `flutter
doctor` shows the checkmark you're grepping for, but the script still says
FAIL).** This is a real, general bash gotcha, not specific to Flutter:
`grep -q` exits the instant it finds its first match, closing the pipe it's
reading from. If the producer on the other end (here, `flutter doctor`) is
still writing when that happens, it receives `SIGPIPE`, and under
`pipefail`, that shows up as the whole pipeline "failing" even though
`grep -q` itself succeeded. Fix: capture the producer's output into a
variable first (`OUT=$(cmd)`), then test the variable
(`[[ "$OUT" == *pattern* ]]`), instead of piping live into `grep -q`. Worth
knowing before writing more tooling like `android_preflight_check.sh` — it's
an easy trap to fall into again.
