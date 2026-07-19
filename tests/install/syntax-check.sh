#!/usr/bin/env bash
# bash -n over every installer script — cheap first gate, no execution.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

while IFS= read -r -d '' file; do
  if ! bash -n "$file"; then
    echo "SYNTAX ERROR: $file" >&2
    fail=1
  fi
done < <(find "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts" -name '*.sh' -print0)

if [ "$fail" -eq 0 ]; then
  echo "OK: all scripts pass bash -n"
fi
exit "$fail"
