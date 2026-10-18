#!/usr/bin/env bash
# Shared helpers for tool/*.sh. Source this file; do not execute it.

APP_DIR=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_DEVICE_ID="${FLUTTER_DEVICE_ID:-00008101-00124C4601EB001E}"
BUNDLE_ID="com.thoufeekx.frenchtutor"

# Builds DEFINE_ARGS from secrets.local.properties (or ../.env). Values are
# never echoed.
load_defines() {
  DEFINE_ARGS=()
  DEFINE_ARGS_PRESENT=0
  local file="$APP_DIR/secrets.local.properties"
  [[ -f "$file" ]] || file="$APP_DIR/../.env"
  [[ -f "$file" ]] || return 0
  local key value
  for key in SUPABASE_URL SUPABASE_ANON_KEY GOOGLE_IOS_CLIENT_ID GOOGLE_WEB_CLIENT_ID \
             REVENUECAT_IOS_KEY REVENUECAT_ANDROID_KEY POSTHOG_API_KEY POSTHOG_HOST; do
    value=$(awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }' "$file")
    if [[ -n "$value" ]]; then
      DEFINE_ARGS+=("--dart-define=$key=$value")
      DEFINE_ARGS_PRESENT=1
    fi
  done
  return 0
}

# Refuses to start when another heavy build/drive is active.
guard_no_competing_build() {
  local busy
  busy=$(ps -axo pid,etime,command | grep -E "xcodebuild|flutter_tools.snapshot (run|drive|test)|gradlew|dart-sdk/bin/dartvm.*drive" | grep -v grep | grep -v "tool/" || true)
  if [[ -n "$busy" ]]; then
    echo "BLOCKED: another heavy job is running. Stop it first:" >&2
    echo "$busy" | cut -c1-160 >&2
    exit 3
  fi
}

# Refuses a normal heavy job when another build is active or the machine is
# overloaded. Simulator reset uses only guard_no_competing_build so it remains
# available as the recovery action when simulator startup itself overloads the
# host.
guard_machine() {
  guard_no_competing_build
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
  local devices
  devices=$(xcrun devicectl list devices 2>/dev/null || true)
  if ! printf '%s\n' "$devices" | grep -F "$id" | grep -Eq 'connected|available \(paired\)'; then
    echo "DEVICE NOT CONNECTED: $id" >&2
    printf '%s\n' "$devices" | sed -n 1,8p >&2
    echo "Unlock the phone, trust this Mac, and replug if needed." >&2
    exit 4
  fi
}

# Stops our own app if it is still running on the phone (for example left over
# from an earlier run). A copy still running under a debugger makes Flutter's
# launch fail and fall back to driving Xcode. Only the app whose bundle id is
# ours is stopped; other apps on the phone are never touched. Dev data is
# disposable, so a hard stop is fine.
stop_app_on_device() {
  local id="$1" path pid
  path=$(xcrun devicectl device info apps --device "$id" --bundle-id "$BUNDLE_ID" --verbose 2>/dev/null \
    | grep -m1 'url: Optional(file://' | sed -E 's#.*Application/([^/]+)/Runner.app.*#\1#')
  [[ -n "$path" ]] || return 0
  for pid in $(xcrun devicectl device info processes --device "$id" 2>/dev/null \
    | grep "$path/Runner.app/Runner" | awk '{print $1}'); do
    echo "stopping leftover ParleSprint on the phone (pid $pid)"
    xcrun devicectl device process terminate --device "$id" --pid "$pid" --kill >/dev/null 2>&1 || true
  done
}
