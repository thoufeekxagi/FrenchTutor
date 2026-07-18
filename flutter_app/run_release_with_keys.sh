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

# 30s discovery window: a wireless iPhone that just locked takes a while to
# reappear on the network — the default (short) check produced false "not
# found" failures on back-to-back deploys.
if ! flutter devices --device-timeout 30 2>&1 | grep -q "$DEVICE_ID"; then
  echo "kodekarbon ($DEVICE_ID) not found in 'flutter devices'." >&2
  echo "Check: phone unlocked, on the same Wi-Fi, Settings > General > VPN & Device Management trusts this Mac." >&2
  exit 1
fi

exec flutter run --release \
  -d "$DEVICE_ID" \
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID"
