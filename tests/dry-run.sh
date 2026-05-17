#!/usr/bin/env zsh
set -eu

# Point tests at the in-repo template so they don't depend on the user's
# live config. Must be set before sourcing — harn.zsh fixes _HARN_CONFIG
# from HARN_CONFIG at source time.
HARN_CONFIG="${0:A:h}/../lib/config.template.json"
source "${0:A:h}/../lib/harn.zsh"

# Test: _harn_read_config should emit the raw JSON
out=$(_harn_read_config)
echo "$out" | jq -e '.harness.claude.wire == "anthropic"' > /dev/null \
  && echo "PASS: config reads claude.wire" \
  || { echo "FAIL: config read"; exit 1; }

# Test: _harn_harness_default should return "account" for claude
out=$(_harn_harness_default claude)
[[ "$out" == "account" ]] && echo "PASS: claude default" || { echo "FAIL: claude default (got '$out')"; exit 1; }

# Test: _harn_harness_default should return empty for pi (null)
out=$(_harn_harness_default pi)
[[ -z "$out" ]] && echo "PASS: pi null default" || { echo "FAIL: pi default (got '$out')"; exit 1; }

# Test: _harn_harness_supports should succeed for (claude, account)
if _harn_harness_supports claude account; then echo "PASS: claude supports account"; else echo "FAIL"; exit 1; fi

# Test: _harn_harness_supports should fail for (pi, account)
if _harn_harness_supports pi account; then echo "FAIL: pi should not support account"; exit 1; else echo "PASS: pi rejects account"; fi

# _harn_parse should populate: _A_HARNESS, _A_MODE, _A_MODEL, _A_PASSTHROUGH, _A_SHOW
# Mode positional
_harn_parse claude local qwen3.6
[[ "$_A_HARNESS" == "claude" && "$_A_MODE" == "local" && "$_A_MODEL" == "qwen3.6" ]] \
  && echo "PASS: positional parse" || { echo "FAIL: positional ($_A_HARNESS/$_A_MODE/$_A_MODEL)"; exit 1; }

# Mode short flag
_harn_parse claude -l qwen3.6
[[ "$_A_HARNESS" == "claude" && "$_A_MODE" == "local" && "$_A_MODEL" == "qwen3.6" ]] \
  && echo "PASS: -l short flag" || { echo "FAIL: short flag ($_A_MODE)"; exit 1; }

# Default mode for claude
_harn_parse claude
_harn_resolve_mode
[[ "$_A_MODE" == "account" ]] && echo "PASS: claude default → account" || { echo "FAIL: default ($_A_MODE)"; exit 1; }

# --show flag
_harn_parse claude --show
[[ "$_A_SHOW" == "1" ]] && echo "PASS: --show captured" || { echo "FAIL: --show"; exit 1; }

# Passthrough after --
_harn_parse claude local qwen3.6 -- --dangerously-skip-permissions "prompt"
[[ "${_A_PASSTHROUGH[1]}" == "--dangerously-skip-permissions" && "${_A_PASSTHROUGH[2]}" == "prompt" ]] \
  && echo "PASS: passthrough" || { echo "FAIL: passthrough (${_A_PASSTHROUGH[@]})"; exit 1; }

# --show for account mode should print unset + exec claude
out=$(harn claude --show)
echo "$out" | grep -q 'unset ANTHROPIC_BASE_URL' && echo "PASS: account unsets BASE_URL" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q 'exec claude' && echo "PASS: account execs claude" || { echo "FAIL"; exit 1; }

# Passthrough appears in exec line
out=$(harn claude --show -- -p hello)
echo "$out" | grep -q 'exec claude -p hello' && echo "PASS: account passthrough" || { echo "FAIL: got '$out'"; exit 1; }

# Passthrough containing spaces must be quoted so the --show line is copy-pasteable.
# Eval the exec line into a fake claude that prints argv one-per-line; assert
# the multi-word arg arrived as a single argument.
out=$(harn claude --show -- -p "hello world")
exec_line=$(echo "$out" | grep '^exec ')
fakebin=$(mktemp -d)
cat > "$fakebin/claude" <<'EOF'
#!/usr/bin/env zsh
for a in "$@"; do print -r -- "$a"; done
EOF
chmod +x "$fakebin/claude"
argv=$(PATH="$fakebin:$PATH" zsh -c "${exec_line#exec }")
rm -rf "$fakebin"
[[ "$(echo "$argv" | sed -n '2p')" == "hello world" ]] \
  && echo "PASS: --show quotes spaces in passthrough" \
  || { echo "FAIL: got argv:"; echo "$argv"; exit 1; }

# harn claude local qwen3.6 --show should emit ollama launch line
out=$(harn claude local qwen3.6 --show)
echo "$out" | grep -q 'exec ollama launch claude --model qwen3.6' \
  && echo "PASS: claude local dispatch" || { echo "FAIL: got '$out'"; exit 1; }

# Pi local goes via ollama launch pi
out=$(harn pi local qwen3.6 --show)
echo "$out" | grep -q 'exec ollama launch pi --model qwen3.6' \
  && echo "PASS: pi local dispatch" || { echo "FAIL: got '$out'"; exit 1; }

# Passthrough preserved
out=$(harn claude local qwen3.6 --show -- -p "hello")
echo "$out" | grep -q -- 'exec ollama launch claude --model qwen3.6 -- -p hello' \
  && echo "PASS: local passthrough" || { echo "FAIL: got '$out'"; exit 1; }

# Missing model is an error (exit non-zero, message contains "requires a model")
out=$(harn claude local --show 2>&1 || true)
echo "$out" | grep -q "requires a model" && echo "PASS: missing model error" || { echo "FAIL"; exit 1; }

# Mock op read: returns a fixed fake key. Local function shadows real op binary
# within this script only.
op() {
  if [[ "$1" == "read" ]]; then
    echo "fake-key-for-tests"
    return 0
  fi
  command op "$@"
}

# anthropic-wire gw dispatch (claude)
out=$(harn claude gw anthropic/claude-sonnet-4.5 --show)
echo "$out" | grep -q 'ANTHROPIC_BASE_URL="https://openrouter.ai/api"' && echo "PASS: gw claude base_url" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q 'ANTHROPIC_AUTH_TOKEN="fake-key-for-tests"' && echo "PASS: gw claude auth_token" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q 'exec claude --model anthropic/claude-sonnet-4.5' && echo "PASS: gw claude exec" || { echo "FAIL"; exit 1; }

# openai-wire gw dispatch (pi): key goes via env var, never argv (visible in `ps`)
out=$(harn pi gw openai/gpt-4o --show)
echo "$out" | grep -q 'export OPENROUTER_API_KEY="fake-key-for-tests"' \
  && echo "PASS: gw pi exports key env" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q 'exec pi --provider openrouter --model openai/gpt-4o' \
  && echo "PASS: gw pi exec" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q -- '--api-key' \
  && { echo "FAIL: --api-key leaked onto argv"; exit 1; } \
  || echo "PASS: gw pi no --api-key on argv"

# codex account: openai-wire account mode clears OPENAI_* (not ANTHROPIC_*)
out=$(harn codex --show)
echo "$out" | grep -q 'unset OPENAI_API_KEY OPENAI_BASE_URL' \
  && echo "PASS: codex account unsets OPENAI_*" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q 'exec codex' \
  && echo "PASS: codex account execs codex" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q 'ANTHROPIC' \
  && { echo "FAIL: codex account leaked ANTHROPIC_* unset"; exit 1; } \
  || echo "PASS: codex account no ANTHROPIC_* leak"

# codex gw: harn injects the full provider definition via -c overrides so
# codex doesn't need ~/.codex/config.toml. Routing (base_url) lives in harn config.
out=$(harn codex gw openai/gpt-4o --show)
echo "$out" | grep -q 'export OPENROUTER_API_KEY="fake-key-for-tests"' \
  && echo "PASS: gw codex exports key env" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q -- 'model_providers.openrouter.base_url=https://openrouter.ai/api/v1' \
  && echo "PASS: gw codex injects base_url" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q -- 'model_providers.openrouter.env_key=OPENROUTER_API_KEY' \
  && echo "PASS: gw codex injects env_key" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q -- 'model_providers.openrouter.wire_api=chat' \
  && echo "PASS: gw codex injects wire_api" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q -- '-c model_provider=openrouter --model openai/gpt-4o' \
  && echo "PASS: gw codex selects provider + model" || { echo "FAIL: got '$out'"; exit 1; }

# Missing openai_wire.base_url on the active gateway is a clean error for
# templates that need it. Use a temp config with codex but no openai_wire.
tmpcfg=$(mktemp)
jq 'del(.gateway.openrouter.openai_wire)' "$HARN_CONFIG" > "$tmpcfg"
err=$(HARN_CONFIG="$tmpcfg" zsh -c "
  HARN_CONFIG='$tmpcfg' source '${0:A:h}/../lib/harn.zsh'
  op() { echo fake-key-for-tests; }
  harn codex gw openai/gpt-4o --show 2>&1
" || true)
echo "$err" | grep -q "gw_argv references {base_url}" \
  && echo "PASS: gw codex missing base_url errors clearly" || { echo "FAIL: got '$err'"; exit 1; }
rm -f "$tmpcfg"

# codex local: launcher dispatch identical shape to pi/claude
out=$(harn codex local qwen3.6 --show)
echo "$out" | grep -q 'exec ollama launch codex --model qwen3.6' \
  && echo "PASS: codex local dispatch" || { echo "FAIL: got '$out'"; exit 1; }

# Missing model is an error
out=$(harn claude gw --show 2>&1 || true)
echo "$out" | grep -q "requires a model" && echo "PASS: gw missing model" || { echo "FAIL"; exit 1; }

# Unknown secrets scheme returns a clean error.
out=$(_harn_resolve_key "bogusvault://x/y" 2>&1 || true)
echo "$out" | grep -q "no secrets provider for scheme 'bogusvault'" \
  && echo "PASS: err unknown secrets scheme" || { echo "FAIL: got '$out'"; exit 1; }

# Missing scheme (no ://) errors cleanly.
out=$(_harn_resolve_key "naked-string" 2>&1 || true)
echo "$out" | grep -q "has no scheme" \
  && echo "PASS: err key_ref no scheme" || { echo "FAIL: got '$out'"; exit 1; }

unset -f op  # cleanup mock

# Unknown harness
out=$(harn bogus local foo 2>&1 || true)
echo "$out" | grep -q "unknown harness 'bogus'" && echo "PASS: err unknown harness" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q "known harnesses: claude, codex, pi" && echo "PASS: err lists harnesses" || { echo "FAIL"; exit 1; }

# Pi with no default
out=$(harn pi 2>&1 || true)
echo "$out" | grep -q "no default mode" && echo "PASS: err pi no default" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q "supported modes: gw, local" && echo "PASS: err lists pi modes" || { echo "FAIL"; exit 1; }

# Unsupported mode
out=$(harn pi account 2>&1 || true)
echo "$out" | grep -q "'account' is not supported by harness 'pi'" && echo "PASS: err unsupported" || { echo "FAIL"; exit 1; }

# help
out=$(harn --help)
echo "$out" | grep -q "usage: harn" && echo "PASS: help" || { echo "FAIL"; exit 1; }

# config print (pretty-printed JSON, key_ref visible)
out=$(harn config)
echo "$out" | grep -q '"key_ref": "op://' && echo "PASS: config shows key_ref" || { echo "FAIL"; exit 1; }

# init writes config.json if missing — use a temp dir so we don't disturb real state
tmpdir=$(mktemp -d)
HARN_CONFIG="$tmpdir/config.json" harn config init > /dev/null
[[ -f "$tmpdir/config.json" ]] && echo "PASS: init creates config" || { echo "FAIL"; exit 1; }
jq -e '.harness.claude.wire == "anthropic"' "$tmpdir/config.json" > /dev/null \
  && echo "PASS: init content valid" || { echo "FAIL"; exit 1; }
rm -rf "$tmpdir"

echo "ALL PASS"
