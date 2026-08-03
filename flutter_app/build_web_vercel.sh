#!/usr/bin/env bash
# Vercel build step: compile the Flutter web app with secrets injected from
# Vercel environment variables (Project Settings > Environment Variables).
#
# These are compile-time --dart-define values, so they are BAKED INTO the
# JS bundle and readable by anyone who views source. Only publishable/anon
# keys belong here. SUPABASE_ANON_KEY is safe by design (row-level security
# is what protects data). GEMINI_API_KEY is NOT safe to expose this way; see
# the note at the bottom.
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

# Optional ones: absent just means that feature stays disabled on web.
: "${GOOGLE_WEB_CLIENT_ID:=}"
: "${GEMINI_API_KEY:=}"
: "${OPENROUTER_API_KEY:=}"
: "${SENTRY_DSN:=}"
: "${POSTHOG_API_KEY:=}"
: "${POSTHOG_HOST:=}"

flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"

echo "Built build/web"

# SECURITY NOTE, read before going public:
# GEMINI_API_KEY and OPENROUTER_API_KEY compiled into a web bundle are
# publicly extractable and therefore billable by anyone who finds them. On
# iOS the same defines are far less exposed. Before a public web launch these
# calls should move behind a Supabase edge function that holds the key
# server-side. Acceptable for a private/internal deploy; not for open signup.
