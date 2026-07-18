# Building & Running ParleSprint on kodekarbon (iPhone, over Wi-Fi)

This is the exact procedure used to build and launch the app on the physical iPhone
named **kodekarbon**, connected wirelessly over Wi-Fi (no cable, no Docker, no Xcode
GUI required). Follow it yourself from a terminal, or ask Claude to "launch the app in
kodekarbon" / "build and deploy to my phone" — either way, this is what runs.

There are two modes:
- **Debug** (`run_with_keys.sh`) — for active development. Slower, shows a debug
  banner, stays attached to the terminal, hot-reloads on save.
- **Release** (`run_release_with_keys.sh`) — for actually USING the app day to day.
  Faster at runtime, no debug banner, and once installed it keeps running as a normal
  standalone app even after you close the terminal or disconnect Wi-Fi.

**Use release mode unless you're actively changing code and want hot reload.**

---

## One-time setup (already done on this Mac, listed for a fresh machine)

1. Flutter SDK installed (`flutter --version` should print `3.44.x` or newer).
2. Xcode installed, with the iOS Development team `CF32XUVD59` available for signing
   (already configured in the Xcode project — nothing to do here normally).
3. kodekarbon has been paired with this Mac once over USB, then "Connect via
   Network" was enabled in Xcode's Devices & Simulators window. After that, USB is
   never needed again — the phone shows up wirelessly whenever it's on the same Wi-Fi.
4. `flutter_app/secrets.local.properties` exists with real keys (gitignored — never
   committed). If it's missing, copy the template and fill it in:
   ```bash
   cd flutter_app
   cp secrets.local.properties.example secrets.local.properties
   # then edit secrets.local.properties and paste in real GEMINI_API_KEY / OPENROUTER_API_KEY
   ```

---

## Every time: run the app on kodekarbon

### Release mode (recommended — this is what "deploy to my phone" means)

```bash
cd flutter_app
./run_release_with_keys.sh
```

This script:
1. Reads the keys out of `secrets.local.properties`.
2. Confirms kodekarbon is visible to `flutter devices` (fails fast with a clear
   message if not — see Troubleshooting below).
3. Runs `flutter run --release -d <kodekarbon's device id> --dart-define=...` for
   both API keys.

Expect to see, in order:
```
Automatically signing iOS for device deployment using specified development team in Xcode project: CF32XUVD59
Running Xcode build...
Xcode build done.                 ~75-110s
Installing and launching...       ~4-8s
```
Once you see "Installing and launching..." finish, the app is live on the phone. You
can now unplug/close the terminal — it keeps running as a normal installed app. Press
`q` in the terminal first if you want to cleanly detach (optional, not required).

### Debug mode (only when actively coding)

```bash
cd flutter_app
./run_with_keys.sh
```

Same idea, but debug build + hot reload (`r` to hot reload, `R` to hot restart, `q` to
quit). Slower to start, shows the debug banner, and the app stops if you close the
terminal or lose the connection.

---

## Doing it by hand (what the scripts do, spelled out)

If you ever need to run this manually instead of via the script:

```bash
cd flutter_app

# 1. Confirm the phone is visible
flutter devices
# Look for a line like:
#   kodekarbon (wireless) (mobile) • 00008101-00124C4601EB001E • ios • iOS 26.x

# 2. Read the keys
GEMINI_KEY=$(grep '^GEMINI_API_KEY=' secrets.local.properties | sed 's/^GEMINI_API_KEY=//')
OPENROUTER_KEY=$(grep '^OPENROUTER_API_KEY=' secrets.local.properties | sed 's/^OPENROUTER_API_KEY=//')

# 3. Build + install + launch (release mode)
flutter run --release \
  -d 00008101-00124C4601EB001E \
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY"
```

**Why the `--dart-define` flags matter, specifically:** the API keys are compiled INTO
the binary at build time (`String.fromEnvironment` in `lib/config/api_keys.dart`), not
read from a file at runtime. If you build without passing them — e.g. a plain
`flutter run --release -d kodekarbon` with no `--dart-define`s — the app installs and
opens fine, but every AI feature (live calls, session scoring, scene generation)
silently fails with empty keys. This was the exact cause of a "the app does nothing
when I start a session" report — the build had compiled with no keys at all. Always
use the scripts, or the manual command above with both keys included.

---

## Troubleshooting — "it fails to deploy" checklist

Run through these in order when a deploy doesn't work:

1. **`flutter devices` doesn't list kodekarbon.**
   - Phone must be unlocked (or at least woken/on the lock screen) and on the **same
     Wi-Fi network** as this Mac.
   - `flutter devices` can take 10-20s to find wireless devices on a cold check —
     wait for the "Checking for wireless devices..." line to finish.
   - If it's still missing, the wireless pairing may have dropped: plug the phone in
     over USB once, open Xcode → Window → Devices and Simulators, confirm kodekarbon
     shows "Connected" with a network icon, then unplug and try again.

2. **`No valid code signing certificates` / signing errors.**
   - Open `flutter_app/ios/Runner.xcworkspace` in Xcode once, select the Runner
     target → Signing & Capabilities, confirm the team is set (should already be
     `CF32XUVD59`) and there's no red error banner. Close Xcode and retry the script.

3. **Build succeeds but install fails / "could not install" / "untrusted developer".**
   - On the phone: Settings → General → VPN & Device Management → find the
     developer certificate → Trust it. This is usually only needed once per
     reinstall of Xcode or once every ~7 days on a free (non-paid) Apple developer
     account — if builds start failing to install after working fine before, this
     is the first thing to check.

4. **App installs but sessions/live calls do nothing.**
   - This is almost always the missing `--dart-define` problem described above —
     confirm you used `run_release_with_keys.sh` (or included both dart-defines by
     hand), not a bare `flutter run`.
   - Double check `secrets.local.properties` actually has non-empty values for both
     keys (`cat flutter_app/secrets.local.properties`).

5. **Build is very slow / seems stuck on "Running Xcode build...".**
   - Normal range is ~75-110 seconds for a release build on this project. If it's
     been several minutes with no output, Ctrl-C and retry — an interrupted previous
     build can sometimes leave stale state; `flutter clean` in `flutter_app/` before
     retrying if a second attempt also hangs.

6. **Wi-Fi deploy is flaky / times out mid-transfer.**
   - Wireless installs are inherently slower and less reliable than USB. If it fails
     repeatedly, plug in via USB cable for that one run (`flutter run --release -d
     <device-id> ...` works identically over USB), then switch back to wireless once
     the phone has re-synced.

---

## Asking Claude to do this

Just say **"launch the app on kodekarbon"** or **"build and deploy the release
version to my phone"** in a session — it will run through this exact procedure
(check devices, read keys, build+install release, confirm it launched) without
needing this document pasted in. This file exists so you can run it yourself too,
and so it's documented once instead of re-explained every session.
