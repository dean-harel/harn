#!/bin/bash
# Runs the suite under whatever bash invokes it; CI uses /bin/bash on macOS for 3.2.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
for t in "$ROOT"/tests/t_*.sh; do
  # shellcheck disable=SC1090 # each test file in turn
  . "$t"
done
printf '%d passed, %d failed\n' "$T_PASS" "$T_FAIL"
[ "$T_FAIL" = 0 ]
