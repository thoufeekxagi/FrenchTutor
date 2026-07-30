#!/bin/bash
# Release-mode counterpart to run_with_keys.sh — see BUILD_FLUTTER_TO_IPHONE.md.
# Builds and installs a RELEASE binary (not debug) on kodekarbon so it keeps running
# standalone after Xcode/Flutter disconnects, with no debug banner.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE_ID="00008101-00124C4601EB001E" # kodekarbon

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

# No standalone "flutter devices" pre-check here on purpose — that scan
# goes through wireless Bonjour/mDNS discovery independently of `flutter run`
# and is flaky in its own right (observed failing 3+ times in a row, then
# succeeding moments later with nothing else changed), so it was producing
# false "not found" failures even when the phone was reachable fine.
# `flutter run -d <id>` below does its own device resolution/wait
# internally and is what run_with_keys.sh (the debug counterpart) has
# always relied on directly, with no separate pre-check — same approach here.
exec flutter run --release \
  -d "$DEVICE_ID" \
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=REVENUECAT_IOS_KEY="$REVENUECAT_IOS_KEY" \
  --dart-define=REVENUECAT_ANDROID_KEY="$REVENUECAT_ANDROID_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"
