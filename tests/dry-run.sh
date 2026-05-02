#!/usr/bin/env zsh
set -eu
source ~/agent/lib/agent.zsh

AGENT_CONFIG=~/.config/agent/config.template.json

# Test: _agent_read_config should emit the raw JSON
out=$(_agent_read_config)
echo "$out" | jq -e '.harness.claude.wire == "anthropic"' > /dev/null \
  && echo "PASS: config reads claude.wire" \
  || { echo "FAIL: config read"; exit 1; }

# Test: _agent_harness_default should return "account" for claude
out=$(_agent_harness_default claude)
[[ "$out" == "account" ]] && echo "PASS: claude default" || { echo "FAIL: claude default (got '$out')"; exit 1; }

# Test: _agent_harness_default should return empty for pi (null)
out=$(_agent_harness_default pi)
[[ -z "$out" ]] && echo "PASS: pi null default" || { echo "FAIL: pi default (got '$out')"; exit 1; }

# Test: _agent_harness_supports should succeed for (claude, account)
if _agent_harness_supports claude account; then echo "PASS: claude supports account"; else echo "FAIL"; exit 1; fi

# Test: _agent_harness_supports should fail for (pi, account)
if _agent_harness_supports pi account; then echo "FAIL: pi should not support account"; exit 1; else echo "PASS: pi rejects account"; fi

# _agent_parse should populate: _A_HARNESS, _A_MODE, _A_MODEL, _A_PASSTHROUGH, _A_SHOW
# Mode positional
_agent_parse claude local qwen3.6
[[ "$_A_HARNESS" == "claude" && "$_A_MODE" == "local" && "$_A_MODEL" == "qwen3.6" ]] \
  && echo "PASS: positional parse" || { echo "FAIL: positional ($_A_HARNESS/$_A_MODE/$_A_MODEL)"; exit 1; }

# Mode short flag
_agent_parse claude -l qwen3.6
[[ "$_A_HARNESS" == "claude" && "$_A_MODE" == "local" && "$_A_MODEL" == "qwen3.6" ]] \
  && echo "PASS: -l short flag" || { echo "FAIL: short flag ($_A_MODE)"; exit 1; }

# Default mode for claude
_agent_parse claude
_agent_resolve_mode
[[ "$_A_MODE" == "account" ]] && echo "PASS: claude default → account" || { echo "FAIL: default ($_A_MODE)"; exit 1; }

# --show flag
_agent_parse claude --show
[[ "$_A_SHOW" == "1" ]] && echo "PASS: --show captured" || { echo "FAIL: --show"; exit 1; }

# Passthrough after --
_agent_parse claude local qwen3.6 -- --dangerously-skip-permissions "prompt"
[[ "${_A_PASSTHROUGH[1]}" == "--dangerously-skip-permissions" && "${_A_PASSTHROUGH[2]}" == "prompt" ]] \
  && echo "PASS: passthrough" || { echo "FAIL: passthrough (${_A_PASSTHROUGH[@]})"; exit 1; }

# --show for account mode should print unset + exec claude
out=$(agent claude --show)
echo "$out" | grep -q 'unset ANTHROPIC_BASE_URL' && echo "PASS: account unsets BASE_URL" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q 'exec claude' && echo "PASS: account execs claude" || { echo "FAIL"; exit 1; }

# Passthrough appears in exec line
out=$(agent claude --show -- -p hello)
echo "$out" | grep -q 'exec claude -p hello' && echo "PASS: account passthrough" || { echo "FAIL: got '$out'"; exit 1; }

# agent claude local qwen3.6 --show should emit ollama launch line
out=$(agent claude local qwen3.6 --show)
echo "$out" | grep -q 'exec ollama launch claude --model qwen3.6' \
  && echo "PASS: claude local dispatch" || { echo "FAIL: got '$out'"; exit 1; }

# Pi local goes via ollama launch pi
out=$(agent pi local qwen3.6 --show)
echo "$out" | grep -q 'exec ollama launch pi --model qwen3.6' \
  && echo "PASS: pi local dispatch" || { echo "FAIL: got '$out'"; exit 1; }

# Passthrough preserved
out=$(agent claude local qwen3.6 --show -- -p "hello")
echo "$out" | grep -q -- 'exec ollama launch claude --model qwen3.6 -- -p hello' \
  && echo "PASS: local passthrough" || { echo "FAIL: got '$out'"; exit 1; }

# Missing model is an error (exit non-zero, message contains "requires a model")
out=$(agent claude local --show 2>&1 || true)
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
out=$(agent claude gw anthropic/claude-sonnet-4.5 --show)
echo "$out" | grep -q 'ANTHROPIC_BASE_URL="https://openrouter.ai/api"' && echo "PASS: gw claude base_url" || { echo "FAIL: got '$out'"; exit 1; }
echo "$out" | grep -q 'ANTHROPIC_AUTH_TOKEN="fake-key-for-tests"' && echo "PASS: gw claude auth_token" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q 'exec claude --model anthropic/claude-sonnet-4.5' && echo "PASS: gw claude exec" || { echo "FAIL"; exit 1; }

# openai-wire gw dispatch (pi)
out=$(agent pi gw openai/gpt-4o --show)
echo "$out" | grep -q 'exec pi --provider openrouter --model openai/gpt-4o --api-key fake-key-for-tests' && echo "PASS: gw pi dispatch" || { echo "FAIL: got '$out'"; exit 1; }

# Missing model is an error
out=$(agent claude gw --show 2>&1 || true)
echo "$out" | grep -q "requires a model" && echo "PASS: gw missing model" || { echo "FAIL"; exit 1; }

unset -f op  # cleanup mock

# Unknown harness
out=$(agent bogus local foo 2>&1 || true)
echo "$out" | grep -q "unknown harness 'bogus'" && echo "PASS: err unknown harness" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q "known harnesses: claude, pi" && echo "PASS: err lists harnesses" || { echo "FAIL"; exit 1; }

# Pi with no default
out=$(agent pi 2>&1 || true)
echo "$out" | grep -q "no default mode" && echo "PASS: err pi no default" || { echo "FAIL"; exit 1; }
echo "$out" | grep -q "supported modes: gw, local" && echo "PASS: err lists pi modes" || { echo "FAIL"; exit 1; }

# Unsupported mode
out=$(agent pi account 2>&1 || true)
echo "$out" | grep -q "'account' is not supported by harness 'pi'" && echo "PASS: err unsupported" || { echo "FAIL"; exit 1; }

# help
out=$(agent --help)
echo "$out" | grep -q "usage: agent" && echo "PASS: help" || { echo "FAIL"; exit 1; }

# config print (pretty-printed JSON, key_ref visible)
out=$(agent config)
echo "$out" | grep -q '"key_ref": "op://' && echo "PASS: config shows key_ref" || { echo "FAIL"; exit 1; }

# init writes config.json if missing — use a temp dir so we don't disturb real state
tmpdir=$(mktemp -d)
AGENT_CONFIG="$tmpdir/config.json" agent config init > /dev/null
[[ -f "$tmpdir/config.json" ]] && echo "PASS: init creates config" || { echo "FAIL"; exit 1; }
jq -e '.harness.claude.wire == "anthropic"' "$tmpdir/config.json" > /dev/null \
  && echo "PASS: init content valid" || { echo "FAIL"; exit 1; }
rm -rf "$tmpdir"

echo "ALL PASS"
