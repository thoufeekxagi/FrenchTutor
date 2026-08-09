#!/usr/bin/env bash
# Vercel build step: compile the Flutter web app with secrets injected from
# Vercel environment variables (Project Settings > Environment Variables).
#
# These are compile-time --dart-define values, so they are BAKED INTO the
# JS bundle and readable by anyone who views source. Only publishable/anon
# values belong here. AI provider secrets are intentionally excluded from
# this browser build.
set -euo pipefail

export PATH="$HOME/flutter/bin:$PATH"

require() {
  if [ -z "${!1:-}" ]; then
    echo "ERROR: required environment variable $1 is not set in Vercel." >&2
    exit 1
  fi
}
require SUPABASE_URL
require SUPABASE_ANON_KEY

reject_placeholder() {
  case "${!1}" in
    https://example.supabase.co|*your-project*|your-*)
      echo "ERROR: $1 still contains a placeholder value." >&2
      exit 1
      ;;
  esac
}
reject_placeholder SUPABASE_URL
reject_placeholder SUPABASE_ANON_KEY

# Optional browser-safe values: absent simply disables the related feature.
: "${GOOGLE_WEB_CLIENT_ID:=}"
: "${SENTRY_DSN:=}"
: "${POSTHOG_API_KEY:=}"
: "${POSTHOG_HOST:=}"

# --no-web-resources-cdn: without this, the build loads its rendering engine
# (CanvasKit) from Google's CDN at runtime instead of the copy already
# bundled in this build. That fails with a blank white screen and no visible
# error for any visitor whose browser/network/ad-blocker can't reach the CDN
# (confirmed live: this is exactly what happened testing in Safari). Costs
# nothing to disable since the engine ships locally either way.
flutter build web --release \
  --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"

echo "Built build/web"

# AI calls are intentionally absent from this client build. Before enabling
# them for public signup, route them through a server-side function that holds
# provider secrets outside the browser bundle.
