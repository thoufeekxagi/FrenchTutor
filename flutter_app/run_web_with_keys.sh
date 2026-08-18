#!/bin/bash
# Local-only helper for the web target — reads public/optional app configuration
# from secrets.local.properties so a plain `flutter run -d web-server` doesn't hit the
# "Bad state: Missing SUPABASE_URL / SUPABASE_ANON_KEY" startup crash.
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

exec flutter run \
  -d web-server --web-port 8734 --web-hostname 127.0.0.1 \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=REVENUECAT_IOS_KEY="$REVENUECAT_IOS_KEY" \
  --dart-define=REVENUECAT_ANDROID_KEY="$REVENUECAT_ANDROID_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"
