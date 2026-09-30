#!/bin/bash
# Runs the suite under whatever bash invokes it; CI uses /bin/bash on macOS for 3.2.
# Usage: tests/run.sh [t_name ...]. Builds .build/harn first, unless HARN_BIN names a binary.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
# Built before lib.sh swaps HOME, so the build uses the real module cache.
if [ -z "${HARN_BIN:-}" ]; then
  (cd "$root" && go build -o .build/harn .) || { printf 'build failed\n'; exit 1; }
fi
# shellcheck source=tests/lib.sh
. "$root/tests/lib.sh"
files=()
if [ $# -eq 0 ]; then
  files=("$ROOT"/tests/t_*.sh)
else
  for n in "$@"; do files+=("$ROOT/tests/$n.sh"); done
fi
for t in "${files[@]}"; do
  # shellcheck disable=SC1090 # each test file in turn
  . "$t"
done
printf '%d passed, %d failed\n' "$T_PASS" "$T_FAIL"
[ "$T_FAIL" = 0 ]
