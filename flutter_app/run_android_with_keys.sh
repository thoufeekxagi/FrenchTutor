#!/bin/bash
# Android counterpart to run_with_keys.sh — see BUILD_FLUTTER_TO_IPHONE.md.
# Reads app configuration from secrets.local.properties (same file the iOS scripts use) and
# runs a DEBUG build on whichever Android device/emulator adb currently sees.
# A plain `flutter run`/`flutter build apk` ships with no keys and the app
# refuses to start with "Bad state: Missing SUPABASE_URL / SUPABASE_ANON_KEY"
# (see lib/config/api_keys.dart + main.dart) — always use this script (or
# build_android_apk_with_keys.sh) instead of calling flutter directly.
set -euo pipefail
cd "$(dirname "$0")"

SECRETS_FILE="secrets.local.properties"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Missing $SECRETS_FILE — copy secrets.local.properties.example to $SECRETS_FILE and fill in real keys." >&2
  exit 1
fi
SUPABASE_URL=$(grep '^SUPABASE_URL=' "$SECRETS_FILE" | sed 's/^SUPABASE_URL=//')
SUPABASE_ANON_KEY=$(grep '^SUPABASE_ANON_KEY=' "$SECRETS_FILE" | sed 's/^SUPABASE_ANON_KEY=//')
GOOGLE_IOS_CLIENT_ID=$(grep '^GOOGLE_IOS_CLIENT_ID=' "$SECRETS_FILE" | sed 's/^GOOGLE_IOS_CLIENT_ID=//')
GOOGLE_WEB_CLIENT_ID=$(grep '^GOOGLE_WEB_CLIENT_ID=' "$SECRETS_FILE" | sed 's/^GOOGLE_WEB_CLIENT_ID=//')
REVENUECAT_IOS_KEY=$(grep '^REVENUECAT_IOS_KEY=' "$SECRETS_FILE" | sed 's/^REVENUECAT_IOS_KEY=//')
REVENUECAT_ANDROID_KEY=$(grep '^REVENUECAT_ANDROID_KEY=' "$SECRETS_FILE" | sed 's/^REVENUECAT_ANDROID_KEY=//')
SENTRY_DSN=$(grep '^SENTRY_DSN=' "$SECRETS_FILE" | sed 's/^SENTRY_DSN=//')
POSTHOG_API_KEY=$(grep '^POSTHOG_API_KEY=' "$SECRETS_FILE" | sed 's/^POSTHOG_API_KEY=//')
POSTHOG_HOST=$(grep '^POSTHOG_HOST=' "$SECRETS_FILE" | sed 's/^POSTHOG_HOST=//')

DEVICE_ID="${1:-}"
DEVICE_FLAG=()
if [ -n "$DEVICE_ID" ]; then
  DEVICE_FLAG=(-d "$DEVICE_ID")
fi

exec flutter run \
  "${DEVICE_FLAG[@]}" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=REVENUECAT_IOS_KEY="$REVENUECAT_IOS_KEY" \
  --dart-define=REVENUECAT_ANDROID_KEY="$REVENUECAT_ANDROID_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"
