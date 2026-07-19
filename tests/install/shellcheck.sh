#!/usr/bin/env bash
# shellcheck -x (follows `source`) over every installer script.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not installed — skipping. Install it to run this check (apt-get install shellcheck / brew install shellcheck)." >&2
  exit 0
fi

fail=0
while IFS= read -r -d '' file; do
  if ! shellcheck -x "$file"; then
    fail=1
  fi
done < <(find "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts" -name '*.sh' -print0)

if [ "$fail" -eq 0 ]; then
  echo "OK: shellcheck clean"
fi
exit "$fail"
