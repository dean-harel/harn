# Subscription path, parsing, --show format, clean environment, settings warning.

run --version
code "version exits 0" "$RC" 0
has "version prints a version" "$OUT" "harn "

run
code "bare harn is a usage error" "$RC" 2
has "bare harn prints usage" "$OUT" "usage: harn <harness>"

run claude --show
code "claude --show exits 0" "$RC" 0
has "labels the subscription" "$OUT" "# source: account (subscription)"
has "unsets anthropic vars" "$OUT" "ANTHROPIC_BASE_URL"
has "unsets openai vars" "$OUT" "OPENAI_BASE_URL"
has "unsets derived provider vars" "$OUT" "OLLAMA_CLOUD_API_KEY"
has "execs claude" "$OUT" "exec claude"

run claude account opus --show
has "account passes a model" "$OUT" "exec claude --model opus"

run pi --show
code "pi has no subscription" "$RC" 2
has "pi message" "$OUT" "pi has no subscription login; use gw, local or a provider"

run bogus --show
code "unknown harness" "$RC" 2
has "unknown harness names known ones" "$OUT" "known harnesses: claude, codex, hermes, pi"

run claude nowhere --show
code "unknown source" "$RC" 2
has "unknown source lists sources" "$OUT" "known: account, gw, local"

run claude --bogus
code "unknown flag" "$RC" 2

# Review Focus 1: passthrough with spaces, quotes and an empty string, in --show and in a real exec.
stub claude 'for a in "$@"; do printf "[%s]\n" "$a"; done'
run claude --show -- -p "hello world" "it's" ""
line=$(printf '%s\n' "$OUT" | grep '^exec ')
pasted=$(PATH="$STUBS:$PATH" /bin/bash -c "${line#exec }")
has "--show line survives a paste (spaces)" "$pasted" "[hello world]"
has "--show line survives a paste (quote)" "$pasted" "[it's]"
has "--show line survives a paste (empty)" "$pasted" "[]"
OUT=$(PATH="$STUBS:$PATH" "$HARN" claude -- -p "hello world" "" 2>&1)
has "real exec keeps spaces" "$OUT" "[hello world]"
has "real exec keeps empty arg" "$OUT" "[]"

# Clean switching on a real exec: inherited gateway variables do not reach the subscription run.
stub claude 'printf "BASE=%s TOKEN=%s\n" "${ANTHROPIC_BASE_URL-unset}" "${ANTHROPIC_AUTH_TOKEN-unset}"'
OUT=$(ANTHROPIC_BASE_URL=https://stale ANTHROPIC_AUTH_TOKEN=stale PATH="$STUBS:$PATH" "$HARN" claude 2>&1)
has "account clears inherited vars" "$OUT" "BASE=unset TOKEN=unset"

# Settings warning on anthropic-wire runs.
mkdir -p "$HOME/.claude"
printf '{"env":{"ANTHROPIC_BASE_URL":"https://x"}}' > "$HOME/.claude/settings.json"
run claude --show
has "warns on settings env" "$OUT" "warning: $HOME/.claude/settings.json sets provider variables"
rm -f "$HOME/.claude/settings.json"
run claude --show
lacks "no warning without settings env" "$OUT" "warning:"

# A slot must name one provider.
OUT=$(HARN_CONFIG=$(cfgwith '.slots.gw = {"*": "openrouter"}') "$HARN" claude gw --show 2>&1); RC=$?
code "object slot is a config error" "$RC" 2
has "object slot names the field" "$OUT" "slots.gw must be a provider name"

# Reserved provider names.
OUT=$(HARN_CONFIG=$(cfgwith '.providers.gw = .providers.openrouter') "$HARN" claude --show 2>&1); RC=$?
code "reserved provider name" "$RC" 2
has "reserved name message" "$OUT" "provider name 'gw' is reserved"

# Review Focus 2: the harness's exit code is harn's own, since harn execs it.
stub claude 'exit 7'
OUT=$(PATH="$STUBS:$PATH" "$HARN" claude 2>&1); RC=$?
code "harness exit code passes through" "$RC" 7

# Review Focus 1: a newline, a dollar sign and a backtick survive the --show paste.
stub claude 'for a in "$@"; do printf "[%s]\n" "$a"; done'
run claude --show -- 'two
lines' '$HOME' '`id`'
line=$(printf '%s\n' "$OUT" | grep '^exec ')
pasted=$(PATH="$STUBS:$PATH" /bin/bash -c "${line#exec }")
has "--show line survives a paste (newline)" "$pasted" "[two
lines]"
has "--show line survives a paste (dollar)" "$pasted" '[$HOME]'
has "--show line survives a paste (backtick)" "$pasted" '[`id`]'

# Review Focus 5: an empty config is a clean config error.
em=$(mktemp); printf '{}' > "$em"
OUT=$(HARN_CONFIG="$em" "$HARN" claude --show 2>&1); RC=$?
code "empty config is a config error" "$RC" 2
has "empty config names the harness" "$OUT" "unknown harness 'claude'"

# Review Focus 2: a harness missing from PATH is named.
nb=$(cfgwith '.harness.claude.binary = "no-such-harness-binary"')
OUT=$(HARN_CONFIG="$nb" "$HARN" claude 2>&1); RC=$?
code "missing harness binary" "$RC" 2
has "missing binary is named" "$OUT" "'no-such-harness-binary' is not on PATH"

# The config file in use heads --show.
run claude --show
first=$(printf '%s\n' "$OUT" | head -n 1)
code "first --show line names the config" "$first" "# config: $HARN_CONFIG"
OUT=$(HARN_CONFIG="$HOME/no-such-dir/config.json" "$HARN" claude --show 2>&1)
has "a missing file shows the built-in template" "$OUT" "# config: built-in template"
lacks "an account run declares no retention" "$OUT" "# retention:"
