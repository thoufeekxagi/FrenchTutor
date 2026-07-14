#!/bin/bash
# Local-only helper (gitignored) — reads keys from secrets.local.properties, which lives
# inside flutter_app itself (see secrets.local.properties.example for the template a new
# dev copies from). Fully self-contained: does not depend on ios_native, which is being
# deprecated. Running this once (or after any `flutter clean`) also bakes DART_DEFINES into
# ios/Flutter/Generated.xcconfig, so subsequent plain Xcode Run-button clicks keep working
# without needing this script again.
set -euo pipefail
cd "$(dirname "$0")"

SECRETS_FILE="secrets.local.properties"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Missing $SECRETS_FILE — copy secrets.local.properties.example to $SECRETS_FILE and fill in real keys." >&2
  exit 1
fi
GEMINI_KEY=$(grep '^GEMINI_API_KEY=' "$SECRETS_FILE" | sed 's/^GEMINI_API_KEY=//')
OPENROUTER_KEY=$(grep '^OPENROUTER_API_KEY=' "$SECRETS_FILE" | sed 's/^OPENROUTER_API_KEY=//')

exec /Users/thoufeekx/development/flutter/bin/flutter run \
  -d 00008101-00124C4601EB001E \
  --dart-define=GEMINI_API_KEY="$GEMINI_KEY" \
  --dart-define=OPENROUTER_API_KEY="$OPENROUTER_KEY"
