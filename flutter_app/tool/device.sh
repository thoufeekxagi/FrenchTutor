#!/usr/bin/env bash
# Fast device helpers built on `xcrun devicectl` (no Xcode GUI, no rebuild).
#
#   tool/device.sh list                 connected devices (about 1s)
#   tool/device.sh relaunch             kill and relaunch the installed app
#   tool/device.sh logs [seconds]       relaunch and stream console output
#   tool/device.sh apps                 is the app installed, and which version
#   tool/device.sh run                  debug build + install + attach (hot reload)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$APP_DIR"
DEVICE="${FLUTTER_DEVICE_ID:-$DEFAULT_DEVICE_ID}"
CMD="${1:-list}"

case "$CMD" in
  list)
    xcrun devicectl list devices ;;
  apps)
    require_device "$DEVICE"
    xcrun devicectl device info apps --device "$DEVICE" 2>&1 | grep -iE "Name|frenchtutor|parlesprint|Bundle" | head ;;
  relaunch)
    require_device "$DEVICE"
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID" ;;
  logs)
    require_device "$DEVICE"
    SECS="${2:-20}"
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console "$BUNDLE_ID" &
    PID=$!
    sleep "$SECS"; kill -TERM "$PID" 2>/dev/null; wait "$PID" 2>/dev/null ;;
  run)
    require_device "$DEVICE"; guard_machine; load_defines
    exec flutter run -d "$DEVICE" ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"} ;;
  *)
    echo "unknown command: $CMD" >&2; exit 2 ;;
esac
