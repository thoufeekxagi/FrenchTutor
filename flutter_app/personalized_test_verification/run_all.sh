#!/bin/bash
# Runs simulate -> verify -> report for a1, a2, b1, b2 in sequence (not
# parallel, to be gentle on Gemini rate limits). Sources GEMINI_API_KEY from
# secrets.local.properties the same way run_with_keys.sh does, so you don't
# have to paste the key inline.
#
# Usage:
#   ./personalized_test_verification/run_all.sh            # all 4 levels, 30 days each
#   ./personalized_test_verification/run_all.sh a1         # just one level
#   DAYS=3 ./personalized_test_verification/run_all.sh a1  # short smoke run
set -euo pipefail
cd "$(dirname "$0")/.."

SECRETS_FILE="secrets.local.properties"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Missing $SECRETS_FILE — copy secrets.local.properties.example to $SECRETS_FILE and fill in a real GEMINI_API_KEY." >&2
  exit 1
fi
GEMINI_API_KEY=$(grep '^GEMINI_API_KEY=' "$SECRETS_FILE" | sed 's/^GEMINI_API_KEY=//')
if [ -z "$GEMINI_API_KEY" ]; then
  echo "GEMINI_API_KEY is empty in $SECRETS_FILE." >&2
  exit 1
fi
export GEMINI_API_KEY

DAYS="${DAYS:-30}"
LEVELS=("$@")
if [ ${#LEVELS[@]} -eq 0 ]; then
  LEVELS=(a1 a2 b1 b2)
fi

echo "Levels: ${LEVELS[*]}   Days per level: $DAYS"
echo "Rough call volume: ~$(( ${#LEVELS[@]} * DAYS * 9 )) Gemini calls total (simulate + judge). This will take a while."

for LEVEL in "${LEVELS[@]}"; do
  echo
  echo "=== $LEVEL: simulating $DAYS days ==="
  LEVEL="$LEVEL" DAYS="$DAYS" GEMINI_API_KEY="$GEMINI_API_KEY" flutter test \
    personalized_test_verification/simulate_journey_test.dart --timeout none

  echo "=== $LEVEL: verifying with judge model ==="
  GEMINI_API_KEY="$GEMINI_API_KEY" dart run personalized_test_verification/verify_journey.dart --level="$LEVEL"

  echo "=== $LEVEL: generating PDF report ==="
  dart run personalized_test_verification/generate_report.dart --level="$LEVEL"
done

echo
echo "Done. Reports in personalized_test_verification/reports/"
