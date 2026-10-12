#!/usr/bin/env bash
# Shared helpers for tool/*.sh. Source this file; do not execute it.

APP_DIR=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_DEVICE_ID="${FLUTTER_DEVICE_ID:-00008101-00124C4601EB001E}"
BUNDLE_ID="com.thoufeekx.frenchtutor"

# Builds DEFINE_ARGS from secrets.local.properties (or ../.env). Values are
# never echoed.
load_defines() {
  DEFINE_ARGS=()
  local file="$APP_DIR/secrets.local.properties"
  [[ -f "$file" ]] || file="$APP_DIR/../.env"
  [[ -f "$file" ]] || return 0
  local key value
  for key in SUPABASE_URL SUPABASE_ANON_KEY GOOGLE_IOS_CLIENT_ID GOOGLE_WEB_CLIENT_ID \
             REVENUECAT_IOS_KEY REVENUECAT_ANDROID_KEY POSTHOG_API_KEY POSTHOG_HOST; do
    value=$(awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }' "$file")
    [[ -n "$value" ]] && DEFINE_ARGS+=("--dart-define=$key=$value")
  done
  return 0
}

# Refuses to start a heavy job when another one is already running, or when
# the machine is overloaded. Rule from the machine safety policy: one build at
# a time, never in parallel.
guard_machine() {
  local busy
  busy=$(ps -axo pid,etime,command | grep -E "xcodebuild|flutter_tools.snapshot (run|drive|test)|gradlew|dart-sdk/bin/dartvm.*drive" | grep -v grep | grep -v "tool/" || true)
  if [[ -n "$busy" ]]; then
    echo "BLOCKED: another heavy job is running. Stop it first:" >&2
    echo "$busy" | cut -c1-160 >&2
    exit 3
  fi
  local load
  load=$(sysctl -n vm.loadavg | awk '{print int($2)}')
  if (( load > 12 )); then
    echo "BLOCKED: load average is $load (limit 12). Wait or lighten the machine." >&2
    exit 3
  fi
}

# Fast device presence check (about 1s). `flutter devices` takes about 6s.
require_device() {
  local id="$1"
  if ! xcrun devicectl list devices 2>/dev/null | grep -F "$id" | grep -q "connected"; then
    echo "DEVICE NOT CONNECTED: $id" >&2
    xcrun devicectl list devices 2>&1 | sed -n 1,8p >&2
    echo "Unlock the phone, trust this Mac, and replug if needed." >&2
    exit 4
  fi
}
