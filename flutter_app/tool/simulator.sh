#!/usr/bin/env bash
# One-device iOS Simulator workflow. All app builds are DEBUG developer builds.
#
#   tool/simulator.sh list
#   tool/simulator.sh boot
#   tool/simulator.sh build
#   tool/simulator.sh test [integration_test/file.dart] [max-seconds]
#   tool/simulator.sh run [flutter run arguments...]
#   tool/simulator.sh screenshot [name]
#   tool/simulator.sh reset      # erases the dedicated simulator device
#   tool/simulator.sh shutdown
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$APP_DIR"

DEFAULT_SIMULATOR_ID="EC2456A5-91A6-47DA-9B47-03E6F3E08F58"
SIMULATOR_ID="${FLUTTER_SIMULATOR_ID:-$DEFAULT_SIMULATOR_ID}"
ACTION="${1:-list}"
if (( $# > 0 )); then shift; fi

booted_ids() {
  xcrun simctl list devices booted --json | python3 -c '
import json, sys
devices = json.load(sys.stdin).get("devices", {})
for group in devices.values():
    for device in group:
        if device.get("state") == "Booted":
            print(device["udid"])
'
}

require_simulator() {
  if ! xcrun simctl list devices available --json | python3 -c '
import json, sys
target = sys.argv[1]
devices = json.load(sys.stdin).get("devices", {})
sys.exit(0 if any(d.get("udid") == target for group in devices.values() for d in group) else 1)
' "$SIMULATOR_ID"; then
    echo "Simulator not available: $SIMULATOR_ID" >&2
    xcrun simctl list devices available >&2
    return 1
  fi
}

stop_other_simulators() {
  local id
  while IFS= read -r id; do
    [[ -z "$id" || "$id" == "$SIMULATOR_ID" ]] && continue
    echo "Shutting down other booted simulator: $id"
    xcrun simctl shutdown "$id"
  done < <(booted_ids)
}

ensure_one_simulator() {
  require_simulator
  stop_other_simulators
  if ! booted_ids | grep -Fxq "$SIMULATOR_ID"; then
    xcrun simctl boot "$SIMULATOR_ID"
  fi
  xcrun simctl bootstatus "$SIMULATOR_ID" -b
  local simulator_app
  simulator_app="$(xcode-select -p)/Applications/Simulator.app"
  if [[ -d "$simulator_app" ]]; then
    open "$simulator_app" --args -CurrentDeviceUDID "$SIMULATOR_ID"
  else
    echo "Simulator.app GUI is not installed; continuing with the booted CoreSimulator device."
  fi
  local ids
  ids=$(booted_ids)
  if [[ "$ids" != "$SIMULATOR_ID" ]]; then
    echo "Expected only $SIMULATOR_ID booted; found: ${ids:-none}" >&2
    return 1
  fi
}

require_only_target_booted() {
  local ids
  ids=$(booted_ids)
  if [[ "$ids" != "$SIMULATOR_ID" ]]; then
    echo "Expected only $SIMULATOR_ID booted; run 'tool/simulator.sh boot' first." >&2
    echo "Booted simulators: ${ids:-none}" >&2
    return 1
  fi
}

require_debug_build() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --release|--profile|--no-debug)
        echo "Simulator iteration is Debug-only; refusing build mode: $arg" >&2
        return 2
        ;;
    esac
  done
}

case "$ACTION" in
  list)
    xcrun simctl list devices available ;;
  boot)
    guard_machine
    ensure_one_simulator
    echo "Ready: $SIMULATOR_ID (one simulator booted)" ;;
  build)
    require_debug_build "$@"
    guard_machine
    ensure_one_simulator
    load_defines
    BUILD_ARGS=(ios --simulator --debug --no-codesign --no-pub)
    if (( DEFINE_ARGS_PRESENT )); then BUILD_ARGS+=("${DEFINE_ARGS[@]}"); fi
    BUILD_ARGS+=("$@")
    flutter build "${BUILD_ARGS[@]}" ;;
  run)
    require_debug_build "$@"
    guard_machine
    ensure_one_simulator
    load_defines
    RUN_ARGS=(run --debug -d "$SIMULATOR_ID")
    if (( DEFINE_ARGS_PRESENT )); then RUN_ARGS+=("${DEFINE_ARGS[@]}"); fi
    RUN_ARGS+=("$@")
    exec flutter "${RUN_ARGS[@]}" ;;
  test)
    guard_machine
    ensure_one_simulator
    load_defines
    TARGET="${1:-integration_test/smoke_test.dart}"
    MAX_SECONDS="${2:-240}"
    [[ -f "$TARGET" ]] || { echo "No such test: $TARGET" >&2; exit 2; }
    RUN_ID="$(date +%Y%m%d-%H%M%S)"
    RUN_DIR="artifacts/simulator/e2e-$RUN_ID"
    while [[ -e "$RUN_DIR" ]]; do
      RUN_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"
      RUN_DIR="artifacts/simulator/e2e-$RUN_ID"
    done
    mkdir -p "$RUN_DIR/shots"
    shift || true
    shift || true
    if [[ -n "${SIMULATOR_DART_DEFINES:-}" ]]; then
      # shellcheck disable=SC2206
      USER_DEFINES=( ${SIMULATOR_DART_DEFINES} )
    fi
    DRIVE_ARGS=(
      --driver=test_driver/integration_test.dart
      --target="$TARGET"
      -d "$SIMULATOR_ID"
      --debug
      --no-pub
      --dart-define=REVIEW_BUILD=true
    )
    if (( DEFINE_ARGS_PRESENT )); then DRIVE_ARGS+=("${DEFINE_ARGS[@]}"); fi
    if [[ -n "${SIMULATOR_DART_DEFINES:-}" ]]; then
      DRIVE_ARGS+=("${USER_DEFINES[@]}")
    fi
    START="$(date +%s)"
    E2E_ARTIFACT_DIR="$RUN_DIR" flutter drive "${DRIVE_ARGS[@]}" \
      > "$RUN_DIR/run.log" 2>&1 &
    PID=$!
    TIMED_OUT=0
    while kill -0 "$PID" 2>/dev/null; do
      if (( $(date +%s) - START > MAX_SECONDS )); then
        pkill -TERM -P "$PID" 2>/dev/null || true
        kill -TERM "$PID" 2>/dev/null || true
        TIMED_OUT=1
        break
      fi
      sleep 2
    done
    set +e
    wait "$PID"
    CODE=$?
    set -e
    if (( TIMED_OUT )); then
      echo "TIMEOUT after ${MAX_SECONDS}s" | tee "$RUN_DIR/result.txt"
      exit 1
    fi
    if (( CODE == 0 )) && grep -q "All tests passed" "$RUN_DIR/run.log"; then
      echo "PASS" > "$RUN_DIR/result.txt"
    else
      echo "FAIL (exit $CODE)" > "$RUN_DIR/result.txt"
    fi
    echo "== $(cat "$RUN_DIR/result.txt"); artifacts: $RUN_DIR"
    grep -E "Xcode build done|All tests passed|Some tests failed|Expected:|Actual:|══╡" "$RUN_DIR/run.log" | tail -12 || true
    [[ "$(cat "$RUN_DIR/result.txt")" == "PASS" ]] ;;
  screenshot)
    require_only_target_booted
    NAME="${1:-$(date +%Y%m%d-%H%M%S)}"
    [[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
      echo "Screenshot name may contain only letters, numbers, dot, dash and underscore." >&2
      exit 2
    }
    SHOT_DIR="artifacts/simulator/shots"
    SHOT_PATH="$SHOT_DIR/$NAME.png"
    [[ ! -e "$SHOT_PATH" ]] || { echo "Refusing to overwrite $SHOT_PATH" >&2; exit 2; }
    mkdir -p "$SHOT_DIR"
    xcrun simctl io "$SIMULATOR_ID" screenshot "$SHOT_PATH"
    echo "Saved: $SHOT_PATH" ;;
  reset)
    guard_no_competing_build
    require_simulator
    stop_other_simulators
    if booted_ids | grep -Fxq "$SIMULATOR_ID"; then
      xcrun simctl shutdown "$SIMULATOR_ID"
    fi
    xcrun simctl erase "$SIMULATOR_ID"
    ensure_one_simulator
    echo "Erased and restarted dedicated developer simulator: $SIMULATOR_ID" ;;
  shutdown)
    stop_other_simulators
    if booted_ids | grep -Fxq "$SIMULATOR_ID"; then
      xcrun simctl shutdown "$SIMULATOR_ID"
    fi
    echo "Shutdown: $SIMULATOR_ID" ;;
  *)
    echo "unknown action: $ACTION" >&2
    exit 2 ;;
esac
