#!/usr/bin/env bash
# Canonical local Flutter entry point.
#
# Usage:
#   ./run_app.sh              # release run on the configured iPhone
#   ./run_app.sh debug        # explicit debug run when needed
#   ./run_app.sh release      # release run on the configured iPhone
#   ./run_app.sh ipa          # build a release IPA for distribution/TestFlight
#
# Local values are read from secrets.local.properties when it exists. Supabase
# production public values also have safe Dart fallbacks, so this script does
# not require a secrets file just to start the app.
set -euo pipefail

APP_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$APP_DIR"

MODE="release"
DEVICE_ID="${FLUTTER_DEVICE_ID:-00008101-00124C4601EB001E}"

usage() {
  cat <<'EOF'
Usage: ./run_app.sh [debug|release|ipa] [--device DEVICE_ID]

  debug    Run the app in debug mode (explicit opt-in).
  release  Run the release build on the configured device (default).
  ipa      Build a release IPA for distribution/TestFlight.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    debug|release|ipa)
      MODE="$1"
      shift
      ;;
    --release)
      MODE="release"
      shift
      ;;
    --device)
      if [[ $# -lt 2 ]]; then
        echo "--device requires a device ID" >&2
        exit 2
      fi
      DEVICE_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN=$(command -v flutter)
elif [[ -x /Users/thoufeekx/development/flutter/bin/flutter ]]; then
  FLUTTER_BIN=/Users/thoufeekx/development/flutter/bin/flutter
else
  echo "Flutter was not found. Add Flutter to PATH and try again." >&2
  exit 1
fi

SECRETS_FILE="$APP_DIR/secrets.local.properties"
DEFINE_ARGS=()

get_property() {
  local key="$1"
  awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }' "$SECRETS_FILE"
}

if [[ -f "$SECRETS_FILE" ]]; then
  for key in \
    SUPABASE_URL \
    SUPABASE_ANON_KEY \
    GOOGLE_IOS_CLIENT_ID \
    GOOGLE_WEB_CLIENT_ID \
    REVENUECAT_IOS_KEY \
    REVENUECAT_ANDROID_KEY \
    SENTRY_DSN \
    POSTHOG_API_KEY \
    POSTHOG_HOST; do
    value=$(get_property "$key")
    if [[ -n "$value" ]]; then
      DEFINE_ARGS+=("--dart-define=$key=$value")
    fi
  done
  echo "Using local configuration from secrets.local.properties (values hidden)."
else
  echo "No secrets.local.properties found; using built-in public Supabase configuration."
  echo "AI requests use the authenticated Supabase Edge Functions."
fi

case "$MODE" in
  debug)
    exec "$FLUTTER_BIN" run -d "$DEVICE_ID" "${DEFINE_ARGS[@]}"
    ;;
  release)
    exec "$FLUTTER_BIN" run --release -d "$DEVICE_ID" "${DEFINE_ARGS[@]}"
    ;;
  ipa)
    exec "$FLUTTER_BIN" build ipa --release "${DEFINE_ARGS[@]}"
    ;;
esac
