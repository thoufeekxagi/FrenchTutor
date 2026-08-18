#!/usr/bin/env bash
# Backward-compatible alias. Use ./run_app.sh release for new local runs.
set -euo pipefail
exec "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/run_app.sh" release "$@"
