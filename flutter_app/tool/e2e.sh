#!/usr/bin/env bash
# Run one on-device integration test and collect artifacts.
#
#   tool/e2e.sh integration_test/smoke_test.dart [device-id] [max-seconds]
#
# Outputs (always under artifacts/e2e/):
#   run.log        full flutter drive log
#   probe.json     everything interactive on each captured screen
#   shots/*.png    screenshots taken with Probe.capture
#   result.txt     PASS / FAIL / TIMEOUT + elapsed seconds
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$APP_DIR"

TARGET="${1:?usage: tool/e2e.sh integration_test/<name>_test.dart [device-id] [max-seconds]}"
DEVICE="${2:-$DEFAULT_DEVICE_ID}"
MAX="${3:-600}"

[[ -f "$TARGET" ]] || { echo "No such test file: $TARGET" >&2; exit 2; }
require_device "$DEVICE"
guard_machine
load_defines

rm -rf artifacts/e2e && mkdir -p artifacts/e2e/shots
START=$(date +%s)

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target="$TARGET" \
  -d "$DEVICE" \
  --no-pub \
  ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"} \
  ${E2E_DEFINES:-} \
  > artifacts/e2e/run.log 2>&1 &
PID=$!

# Watchdog: a drive that never reaches the VM service hangs forever on white
# screen. Kill it, report, and stop instead of retrying blindly.
while kill -0 "$PID" 2>/dev/null; do
  NOW=$(date +%s)
  if (( NOW - START > MAX )); then
    pkill -TERM -P "$PID" 2>/dev/null; kill -TERM "$PID" 2>/dev/null
    echo "TIMEOUT after ${MAX}s" > artifacts/e2e/result.txt
    break
  fi
  if grep -q "Dart VM Service was not discovered" artifacts/e2e/run.log 2>/dev/null && (( NOW - START > 150 )); then
    pkill -TERM -P "$PID" 2>/dev/null; kill -TERM "$PID" 2>/dev/null
    echo "TIMEOUT: VM service never discovered (app not launching)" > artifacts/e2e/result.txt
    break
  fi
  sleep 2
done
wait "$PID" 2>/dev/null
CODE=$?
ELAPSED=$(( $(date +%s) - START ))

if [[ ! -s artifacts/e2e/result.txt ]]; then
  if grep -q "All tests passed" artifacts/e2e/run.log && (( CODE == 0 )); then
    echo "PASS" > artifacts/e2e/result.txt
  else
    echo "FAIL (exit $CODE)" > artifacts/e2e/result.txt
  fi
fi
echo "elapsed: ${ELAPSED}s" >> artifacts/e2e/result.txt

echo "== $(head -1 artifacts/e2e/result.txt) in ${ELAPSED}s"
echo "== screenshots: $(ls artifacts/e2e/shots 2>/dev/null | wc -l | tr -d ' ')   probe: $( [[ -f artifacts/e2e/probe.json ]] && echo artifacts/e2e/probe.json || echo none )"
grep -E "^\s*(Xcode build done|[0-9:]+ \+[0-9]+.*(Some tests failed|All tests passed)|Expected:|Actual:|══╡)" artifacts/e2e/run.log | head -12
head -1 artifacts/e2e/result.txt | grep -q "^PASS"
