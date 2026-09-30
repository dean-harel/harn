# Sourced by tests/run.sh. Every test runs bin/harn as a child process against an isolated HOME.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HARN="${HARN_BIN:-$ROOT/.build/harn}"
T_PASS=0
T_FAIL=0
HOME=$(mktemp -d)
STUBS=$(mktemp -d)
export HOME
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
export HARN_CONFIG="$ROOT/lib/config.template.json"

ok()  { T_PASS=$((T_PASS + 1)); printf 'PASS: %s\n' "$1"; }
bad() { T_FAIL=$((T_FAIL + 1)); printf 'FAIL: %s\n' "$1"; [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/    /'; }
has()   { case $2 in *"$3"*) ok "$1" ;; *) bad "$1" "$2" ;; esac; }
lacks() { case $2 in *"$3"*) bad "$1" "$2" ;; *) ok "$1" ;; esac; }
code()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "exit $2, want $3"; fi; }
# shellcheck disable=SC2034 # OUT and RC are read by the sourced test files
run()   { OUT=$("$HARN" "$@" 2>&1); RC=$?; }
cfgwith() { local f; f=$(mktemp); jq "$1" "$ROOT/lib/config.template.json" > "$f"; printf '%s' "$f"; }
stub()  { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
