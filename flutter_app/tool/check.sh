#!/usr/bin/env bash
# Fast pre-device gate (target: under 60s). Run before every device run and
# before every commit.
#
#   tool/check.sh               format(changed) + analyze + content + all unit/widget tests
#   tool/check.sh test/foo_test.dart test/bar_test.dart    only those tests
#   tool/check.sh --quick       format(changed) + analyze + content only
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$APP_DIR"
FAIL=0
step() { echo; echo "== $*"; }

QUICK=0
TESTS=()
for arg in "$@"; do
  if [[ "$arg" == "--quick" ]]; then QUICK=1; else TESTS+=("$arg"); fi
done

step "format (changed Dart files only)"
CHANGED=$(git ls-files -m -o --exclude-standard -- 'lib/*.dart' 'test/*.dart' 'integration_test/*.dart' 'test_driver/*.dart' 'tool/*.dart' 2>/dev/null | while read -r f; do [[ -f "$f" ]] && echo "$f"; done)
if [[ -n "$CHANGED" ]]; then
  # shellcheck disable=SC2086
  dart format --output=none --set-exit-if-changed $CHANGED || { echo "Run: dart format <the files listed above>"; FAIL=1; }
else
  echo "(no changed Dart files)"
fi

step "analyze (fails only on NEW errors/warnings; baseline in tool/known_analyzer_issues.txt)"
python3 tool/analyze_gate.py || FAIL=1

step "screen map and key lint (lib/v3)"
python3 tool/screen_map.py --check || FAIL=1

CONTENT_VALIDATOR="$APP_DIR/../content/tcf/tools/validate.py"
if [[ -f "$CONTENT_VALIDATOR" ]]; then
  step "content validation"
  python3 "$CONTENT_VALIDATOR" || FAIL=1
fi

if (( QUICK == 0 )); then
  step "unit + widget tests (fails only on NEW failures; baseline in tool/known_test_failures.txt)"
  mkdir -p artifacts
  if (( ${#TESTS[@]} > 0 )); then flutter test --no-pub "${TESTS[@]}" > artifacts/check_tests.log 2>&1
  else flutter test --no-pub > artifacts/check_tests.log 2>&1; fi
  tail -1 artifacts/check_tests.log | cut -c1-120
  grep "\[E\]" artifacts/check_tests.log | sed -E "s#^[0-9:]+ \+[0-9]+( -[0-9]+)?: ##; s# \[E\]\$##; s#$APP_DIR/##" | sort -u > artifacts/check_failed_now.txt
  NEW=$(comm -13 tool/known_test_failures.txt artifacts/check_failed_now.txt)
  if [[ -n "$NEW" ]]; then echo "NEW test failures:"; echo "$NEW"; FAIL=1
  else echo "no new test failures ($(wc -l < artifacts/check_failed_now.txt | tr -d ' ') known baseline failures remain)"; fi
fi

echo
if (( FAIL == 0 )); then echo "CHECK PASSED"; else echo "CHECK FAILED"; fi
exit $FAIL
