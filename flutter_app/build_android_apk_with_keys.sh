#!/bin/bash
# Builds a standalone Android APK (debug by default) with keys baked in via
# --dart-define, then installs it on whatever adb device is connected.
# A plain `flutter build apk` ships with no keys and the app refuses to start
# with "Bad state: Missing SUPABASE_URL / SUPABASE_ANON_KEY" (see
# lib/config/api_keys.dart + main.dart) — always use this script instead of
# calling `flutter build apk` directly.
#
# Usage:
#   ./build_android_apk_with_keys.sh            # debug build, install if a device is attached
#   ./build_android_apk_with_keys.sh --release  # release build
set -euo pipefail
cd "$(dirname "$0")"

BUILD_MODE="debug"
if [ "${1:-}" = "--release" ]; then
  BUILD_MODE="release"
fi

SECRETS_FILE="secrets.local.properties"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Missing $SECRETS_FILE — copy secrets.local.properties.example to $SECRETS_FILE and fill in real keys." >&2
  exit 1
fi
GEMINI_KEY=$(grep '^GEMINI_API_KEY=' "$SECRETS_FILE" | sed 's/^GEMINI_API_KEY=//')
OPENROUTER_KEY=$(grep '^OPENROUTER_API_KEY=' "$SECRETS_FILE" | sed 's/^OPENROUTER_API_KEY=//')
SUPABASE_URL=$(grep '^SUPABASE_URL=' "$SECRETS_FILE" | sed 's/^SUPABASE_URL=//')
SUPABASE_ANON_KEY=$(grep '^SUPABASE_ANON_KEY=' "$SECRETS_FILE" | sed 's/^SUPABASE_ANON_KEY=//')
GOOGLE_IOS_CLIENT_ID=$(grep '^GOOGLE_IOS_CLIENT_ID=' "$SECRETS_FILE" | sed 's/^GOOGLE_IOS_CLIENT_ID=//')
GOOGLE_WEB_CLIENT_ID=$(grep '^GOOGLE_WEB_CLIENT_ID=' "$SECRETS_FILE" | sed 's/^GOOGLE_WEB_CLIENT_ID=//')
REVENUECAT_IOS_KEY=$(grep '^REVENUECAT_IOS_KEY=' "$SECRETS_FILE" | sed 's/^REVENUECAT_IOS_KEY=//')
REVENUECAT_ANDROID_KEY=$(grep '^REVENUECAT_ANDROID_KEY=' "$SECRETS_FILE" | sed 's/^REVENUECAT_ANDROID_KEY=//')
SENTRY_DSN=$(grep '^SENTRY_DSN=' "$SECRETS_FILE" | sed 's/^SENTRY_DSN=//')
POSTHOG_API_KEY=$(grep '^POSTHOG_API_KEY=' "$SECRETS_FILE" | sed 's/^POSTHOG_API_KEY=//')
POSTHOG_HOST=$(grep '^POSTHOG_HOST=' "$SECRETS_FILE" | sed 's/^POSTHOG_HOST=//')

DART_DEFINES=(
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY"
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY"
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID"
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID"
  --dart-define=REVENUECAT_IOS_KEY="$REVENUECAT_IOS_KEY"
  --dart-define=REVENUECAT_ANDROID_KEY="$REVENUECAT_ANDROID_KEY"
  --dart-define=SENTRY_DSN="$SENTRY_DSN"
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY"
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"
)

if [ "$BUILD_MODE" = "release" ]; then
  flutter build apk --release "${DART_DEFINES[@]}"
  APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
else
  flutter build apk --debug "${DART_DEFINES[@]}"
  APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
fi

if adb get-state >/dev/null 2>&1; then
  adb install -r "$APK_PATH"
  echo "Installed $APK_PATH on $(adb get-serialno)."
else
  echo "Built $APK_PATH (no adb device attached, skipped install)."
fi
