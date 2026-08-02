#!/bin/bash
# Run this BEFORE building for Android on a new machine, or any time
# `flutter build apk` fails with a version-y/Gradle-y error you don't
# recognize. It doesn't fix anything — it's read-only — but it catches the
# exact classes of problem that cost hours to diagnose on 2026-08-02:
#   1. Flutter/Dart too old for this project's `environment: sdk:` constraint
#   2. Android SDK/Java toolchain missing or misconfigured
#   3. A plugin in pub-cache hardcoding an old Kotlin languageVersion that
#      this project's Kotlin Gradle Plugin version no longer accepts (the
#      sentry_flutter 8.x bug — see ANDROID_SETUP.md for the full story).
#      This scan checks EVERY installed plugin, not just sentry_flutter, so
#      it also catches the *next* plugin that has this same problem.
#
# Usage: ./android_preflight_check.sh
set -uo pipefail
cd "$(dirname "$0")"

PASS=0
WARN=0
FAIL=0

pass() { echo "  OK   $1"; PASS=$((PASS + 1)); }
warn() { echo "  WARN $1"; WARN=$((WARN + 1)); }
fail() { echo "  FAIL $1"; FAIL=$((FAIL + 1)); }

echo "=== 1. Flutter / Dart SDK ==="
REQUIRED_DART=$(grep -oP "sdk:\s*\^\K[0-9.]+" pubspec.yaml | head -1)
INSTALLED_DART=$(flutter --version --machine 2>/dev/null | grep -oP '"dartSdkVersion":\s*"\K[0-9.]+' || true)
if [ -z "$INSTALLED_DART" ]; then
  fail "Could not read installed Dart SDK version — is 'flutter' on PATH?"
elif [ -z "$REQUIRED_DART" ]; then
  warn "Could not parse required Dart SDK from pubspec.yaml (check manually)"
else
  # simple version compare via sort -V
  LOWEST=$(printf '%s\n%s\n' "$REQUIRED_DART" "$INSTALLED_DART" | sort -V | head -1)
  if [ "$LOWEST" = "$REQUIRED_DART" ]; then
    pass "Dart $INSTALLED_DART satisfies required ^$REQUIRED_DART"
  else
    fail "Dart $INSTALLED_DART is OLDER than required ^$REQUIRED_DART — run 'flutter upgrade'"
  fi
fi

echo ""
echo "=== 2. Android toolchain (flutter doctor) ==="
# Captured into a variable rather than piped straight to grep -q: grep -q
# exits on its first match, closing the pipe early, which can SIGPIPE
# 'flutter doctor' mid-write and (under `pipefail`) surface as a false
# failure here even though the check itself matched fine.
DOCTOR_OUTPUT=$(flutter doctor 2>/dev/null)
if [[ "$DOCTOR_OUTPUT" == *"[✓] Android toolchain"* ]]; then
  pass "Android toolchain OK"
else
  fail "Android toolchain not OK — run 'flutter doctor -v' and fix the Android section"
fi

if command -v java >/dev/null 2>&1; then
  JAVA_VER=$(java -version 2>&1 | head -1)
  pass "Java present: $JAVA_VER"
else
  fail "No 'java' on PATH — Gradle needs a JDK (17 recommended for this project)"
fi

echo ""
echo "=== 3. Project's declared Gradle / AGP / Kotlin versions ==="
GRADLE_V=$(grep -oP 'distributionUrl=.*gradle-\K[0-9.]+' android/gradle/wrapper/gradle-wrapper.properties 2>/dev/null || echo "?")
AGP_V=$(grep -oP 'com\.android\.application.*version\s+"\K[^"]+' android/settings.gradle.kts 2>/dev/null || echo "?")
KOTLIN_V=$(grep -oP 'org\.jetbrains\.kotlin\.android.*version\s+"\K[^"]+' android/settings.gradle.kts 2>/dev/null || echo "?")
echo "  Gradle $GRADLE_V / AGP $AGP_V / Kotlin $KOTLIN_V"
echo "  (These are pinned in the repo — if you didn't change them, they're not the problem.)"

echo ""
echo "=== 4. Scanning pub-cache for plugins with a Kotlin-incompatible languageVersion ==="
echo "  (This is the sentry_flutter 8.x bug's root cause, generalized to catch any plugin.)"
FOUND_ISSUE=0
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
if [ -d "$PUB_CACHE/hosted/pub.dev" ]; then
  while IFS= read -r -d '' gradle_file; do
    match=$(grep -oP 'languageVersion\s*=\s*["'"'"']\K[0-9]+\.[0-9]+' "$gradle_file" 2>/dev/null | head -1)
    if [ -n "$match" ]; then
      major="${match%%.*}"
      # Kotlin 2.2+ rejects languageVersion below 2.0 outright (what bit us today)
      if [ "$major" -lt 2 ]; then
        pkg=$(echo "$gradle_file" | grep -oP '/hosted/pub\.dev/\K[^/]+')
        warn "Plugin '$pkg' hardcodes languageVersion=$match in its android/build.gradle — may break if the project's Kotlin version stops supporting it. Check its changelog for a newer release."
        FOUND_ISSUE=1
      fi
    fi
  done < <(find "$PUB_CACHE/hosted/pub.dev" -maxdepth 3 -path "*/android/build.gradle" -print0 2>/dev/null)
fi
if [ "$FOUND_ISSUE" -eq 0 ]; then
  pass "No installed plugin hardcodes an old Kotlin languageVersion"
fi

echo ""
echo "=== 5. Emulator sanity (if any AVD exists) ==="
if command -v avdmanager >/dev/null 2>&1; then
  AVDS=$(avdmanager list avd 2>/dev/null | grep "Name:" | sed 's/.*Name: //')
  if [ -n "$AVDS" ]; then
    echo "  Existing AVDs:"
    echo "$AVDS" | sed 's/^/    - /'
    pass "At least one AVD exists — remember: always boot with -no-snapshot (see ANDROID_SETUP.md for why)"
  else
    warn "No AVDs found yet — see ANDROID_SETUP.md section 3 to create one"
  fi
else
  warn "avdmanager not found — Android SDK cmdline-tools may not be installed"
fi

echo ""
echo "=== Summary: $PASS OK, $WARN warnings, $FAIL failures ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
