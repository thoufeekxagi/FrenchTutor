#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Create it locally with the Supabase URL and service-role key." >&2
  exit 64
fi

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 exact-email@example.com" >&2
  exit 64
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

: "${SUPABASE_URL:?SUPABASE_URL is missing in $env_file}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is missing in $env_file}"

export DELETE_USER_CONFIRM="$1"
exec dart run "$script_dir/delete_test_user.dart" \
  --email="$1" \
  --execute
