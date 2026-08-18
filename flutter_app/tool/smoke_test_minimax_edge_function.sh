#!/usr/bin/env bash
set -euo pipefail

# Safe MiniMax smoke test for the authenticated ai-image Edge Function.
# This script never prints the Supabase key, access token, provider response,
# or generated image bytes.

: "${SUPABASE_URL:?Set SUPABASE_URL to the Supabase project URL}"
endpoint="${SUPABASE_URL%/}/functions/v1/ai-image"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

if [[ "${1:-}" == "--check-auth-gate" ]]; then
  status="$(curl --silent --show-error --output "$response_file" \
    --write-out '%{http_code}' \
    --request POST \
    -H 'Content-Type: application/json' \
    --data '{"prompt":"auth gate check"}' \
    "$endpoint")"

  if [[ "$status" == "401" || "$status" == "403" ]]; then
    echo "ai-image auth-gate check passed (HTTP $status; unauthenticated calls are blocked)."
    exit 0
  fi

  echo "ai-image auth-gate check failed (expected HTTP 401 or 403, received HTTP $status)."
  exit 1
fi

publishable_key="${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-}}"
: "${publishable_key:?Set SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) to the public Supabase key}"

request_headers=(
  -H "apikey: $publishable_key"
  -H 'Content-Type: application/json'
)

: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN to a current signed-in Supabase access token}"

status="$(curl --silent --show-error --output "$response_file" \
  --write-out '%{http_code}' \
  --request POST "${request_headers[@]}" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  --data '{"prompt":"Create a premium literary book cover titled Smoke Test. Show a blue door, warm light, tactile paper, and no people, animals, or extra text."}' \
  "$endpoint")"

python3 - "$response_file" "$status" <<'PY'
import json
import sys

path, status = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception as exc:
    raise SystemExit(f"ai-image smoke test failed: invalid JSON response (HTTP {status}).") from exc

encoded = payload.get("imageBase64")
if not isinstance(encoded, str) or len(encoded) < 100:
    raise SystemExit(f"ai-image smoke test failed: no image payload received (HTTP {status}).")

print(f"ai-image smoke test passed: MiniMax image payload received ({len(encoded)} base64 characters).")
PY
