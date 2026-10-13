#!/usr/bin/env bash
# Runs every v3 device test on the connected iPhone, one at a time, and prints
# a pass/fail table. Screenshots of each test are kept in artifacts/e2e_all/.
#   tool/e2e_all.sh            all tests (about 15 minutes)
#   tool/e2e_all.sh story      only tests whose file name contains "story"
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$APP_DIR"
DEVICE="${FLUTTER_DEVICE_ID:-$DEFAULT_DEVICE_ID}"
FILTER="${1:-}"
OUT="$APP_DIR/artifacts/e2e_all"
rm -rf "$OUT" && mkdir -p "$OUT"

# The course walk plays every lesson (about an hour). The default run walks a
# representative sample (about 9 minutes). FULL_WALK=1 tool/e2e_all.sh walk
# plays all of them.
if [[ "${FULL_WALK:-}" == "1" ]]; then
  WALK_ONLY_DEFINE=""; WALK_MAX=6000
else
  WALK_ONLY_DEFINE="--dart-define=E2E_ONLY=s0-01,s0-10,a1-u01-words-1,a1-u02-grammar,a1-u03-dialogues,a1-u04-tcf,a1-u05-checkpoint"; WALK_MAX=1500
fi

# file | extra dart-defines | max seconds
TESTS=(
  "v3_onboarding_test.dart|--dart-define=SKIP_NOTIFICATION_PROMPT=true|600"
  "v3_shell_test.dart|--dart-define=E2E_SHELL=true|600"
  "v3_lesson_test.dart|--dart-define=E2E_SHELL=true|600"
  "v3_course_walk_test.dart|--dart-define=E2E_SHELL=true ${WALK_ONLY_DEFINE}|${WALK_MAX}"
  "v3_resume_test.dart|--dart-define=E2E_SHELL=true|600"
  "v3_story_test.dart|--dart-define=E2E_SHELL=true --dart-define=E2E_FAKE_AUDIO=true|900"
)

SUMMARY=()
FAILED=0
for entry in "${TESTS[@]}"; do
  IFS='|' read -r file defs max <<<"$entry"
  [[ -n "$FILTER" && "$file" != *"$FILTER"* ]] && continue
  name="${file%_test.dart}"
  echo "=== $file"
  E2E_DEFINES="$defs" tool/e2e.sh "integration_test/$file" "$DEVICE" "$max" > "$OUT/$name.log" 2>&1
  line=$(grep -E "^== (PASS|FAIL|TIMEOUT)" "$OUT/$name.log" | head -1)
  [[ -z "$line" ]] && line="== NO RESULT"
  mkdir -p "$OUT/$name"
  cp -R artifacts/e2e/shots/. "$OUT/$name/" 2>/dev/null || true
  [[ "$line" == "== PASS"* ]] || FAILED=$((FAILED + 1))
  SUMMARY+=("$(printf '%-28s %s' "$file" "$line")")
  echo "$line"
done

echo
echo "================ v3 device tests ================"
printf '%s\n' "${SUMMARY[@]}"
echo "================================================="
[[ $FAILED -eq 0 ]] && echo "ALL PASSED" || echo "$FAILED FAILED (logs in artifacts/e2e_all/)"
exit $FAILED
