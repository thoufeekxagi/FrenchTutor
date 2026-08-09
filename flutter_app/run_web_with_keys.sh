#!/bin/bash
# Local-only web runner. Builds a release bundle with your local .env keys
# baked in (NEVER commit the build/ dir), serves it on http://127.0.0.1:8734,
# and works in any browser (Firefox, Chrome, Safari). Use like `bun dev`.
#
#   ./run_web_with_keys.sh
#
# Then open http://127.0.0.1:8734 in Firefox. Ctrl-C to stop.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="$SCRIPT_DIR/../.env"
if [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="$SCRIPT_DIR/secrets.local.properties"
fi
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing ../.env and secrets.local.properties. Add real Supabase values before starting web." >&2
  exit 1
fi

read_key() {
  local key="$1"
  local value
  value=$(sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=[[:space:]]*//p" "$CONFIG_FILE" | head -n 1)
  value="${value%$'\r'}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

SUPABASE_URL=$(read_key SUPABASE_URL)
SUPABASE_ANON_KEY=$(read_key SUPABASE_ANON_KEY)
GOOGLE_WEB_CLIENT_ID=$(read_key GOOGLE_WEB_CLIENT_ID)
GEMINI_KEY=$(read_key GEMINI_API_KEY)
OPENROUTER_KEY=$(read_key OPENROUTER_API_KEY)
SENTRY_DSN=$(read_key SENTRY_DSN)
POSTHOG_API_KEY=$(read_key POSTHOG_API_KEY)
POSTHOG_HOST=$(read_key POSTHOG_HOST)

if [[ "$SUPABASE_URL" == "https://example.supabase.co" ||
      "$SUPABASE_URL" == *"your-project"* ||
      -z "$SUPABASE_ANON_KEY" ||
      "$SUPABASE_ANON_KEY" == your-* ]]; then
  echo "Invalid Supabase web configuration. Fill the real SUPABASE_URL and SUPABASE_ANON_KEY in $CONFIG_FILE." >&2
  exit 1
fi

if [ -z "$GEMINI_KEY" ] || [[ "$GEMINI_KEY" == your-* ]]; then
  echo "Missing GEMINI_API_KEY in $CONFIG_FILE. Local web testing needs it for AI calls." >&2
  exit 1
fi

PORT="${WEB_PORT:-8734}"
HOST="${WEB_HOST:-127.0.0.1}"
BUILD_DIR="$SCRIPT_DIR/build/web"

echo "Building Flutter web (release) with local keys..."
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=DEV_UNLOCK_ALL=true \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"

echo
echo "Serving on http://$HOST:$PORT  (Ctrl-C to stop)"
echo "Open in Firefox: http://$HOST:$PORT"
echo
cd "$BUILD_DIR"
exec python3 -m http.server "$PORT" --bind "$HOST"
