#!/bin/bash
# Prepares the project for an Xcode build/archive, doing two jobs EVERY run:
#   1. Auto-increments the iOS build number from the git commit count (always
#      strictly increasing, never collides with a previous TestFlight upload).
#      Skipped if the current number is already ahead.
#   2. Regenerates ios/Flutter/Generated.xcconfig WITH the local dart-defines
#      baked in, so optional/private integrations are present when available.
#      Supabase's public production configuration is compiled into the app as
#      a safe fallback, so a direct Xcode Run/Archive no longer depends on
#      this local script for Supabase startup.
# Run this once before opening Xcode. See BUILD_FLUTTER_TO_IPHONE.md.
set -euo pipefail
cd "$(dirname "$0")"

# --- 1. Build number -------------------------------------------------------
NEXT_BUILD=$(git rev-list --count HEAD)
LAST_MSG=$(git log -1 --pretty=%s)
if [[ "$LAST_MSG" != "Bump iOS build number to "*" [auto]" ]]; then
  NEXT_BUILD=$((NEXT_BUILD + 1)) # +1 for the commit this bump itself will become
  # (skipped when HEAD is already an auto-bump commit — its own count already accounts for it,
  # otherwise re-running this script, e.g. on a retried push, bumps again every time)
fi

CURRENT=$(grep '^version:' pubspec.yaml | sed -E 's/^version: [0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)$/\1/')
if [ "$NEXT_BUILD" -le "$CURRENT" ]; then
  echo "Build number already at $CURRENT (>= computed $NEXT_BUILD) — keeping it."
  EXPECTED_BUILD="$CURRENT"
else
  sed -i '' -E "s/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+/version: \1+$NEXT_BUILD/" pubspec.yaml
  echo "Bumped build number: $CURRENT -> $NEXT_BUILD"
  EXPECTED_BUILD="$NEXT_BUILD"
fi

# --- 2. Regenerate Xcode config WITH keys (always) -------------------------
SECRETS_FILE="secrets.local.properties"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Missing $SECRETS_FILE — copy secrets.local.properties.example and fill in real keys." >&2
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

flutter build ios --config-only \
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  --dart-define=REVENUECAT_IOS_KEY="$REVENUECAT_IOS_KEY" \
  --dart-define=REVENUECAT_ANDROID_KEY="$REVENUECAT_ANDROID_KEY" \
  >/dev/null

# --- 3. Verify, don't trust ------------------------------------------------
ACTUAL=$(grep '^FLUTTER_BUILD_NUMBER=' ios/Flutter/Generated.xcconfig | cut -d= -f2)
if [ "$ACTUAL" != "$EXPECTED_BUILD" ]; then
  echo "ERROR: Generated.xcconfig shows build $ACTUAL, expected $EXPECTED_BUILD — do not archive yet." >&2
  exit 1
fi
# DART_DEFINES entries are base64; "U1VQQUJBU0VfVVJM" is the stable encoding
# of the "SUPABASE_URL" prefix — its presence proves OUR keys are baked in,
# not just Flutter's built-in defines (which exist even in a keyless config).
if grep -q 'U1VQQUJBU0VfVVJM' ios/Flutter/Generated.xcconfig; then
  echo "Generated.xcconfig confirmed: build $ACTUAL, local overrides baked in. Ready for Xcode."
else
  echo "Generated.xcconfig confirmed: build $ACTUAL. Supabase will use its public production fallback; optional local overrides are absent."
fi
