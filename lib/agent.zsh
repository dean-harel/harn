#!/usr/bin/env zsh
# agent: unified launcher for AI coding harnesses.
# Spec: /Users/deanharel/Developer/llm-harness-wrapper/spec.md

_AGENT_CONFIG="${AGENT_CONFIG:-$HOME/Developer/agent/config.json}"
_AGENT_TEMPLATE="$HOME/Developer/agent/lib/config.template.json"

# Emit the raw config JSON. Respects $AGENT_CONFIG override for tests;
# falls back to template if live config does not yet exist, so helpers
# are usable pre-`init`.
_agent_read_config() {
  if [[ -n "${AGENT_CONFIG:-}" && -r "${AGENT_CONFIG}" ]]; then
    cat "${AGENT_CONFIG}"
  elif [[ -r "$_AGENT_CONFIG" ]]; then
    cat "$_AGENT_CONFIG"
  elif [[ -r "$_AGENT_TEMPLATE" ]]; then
    cat "$_AGENT_TEMPLATE"
  else
    echo "error: no config at $_AGENT_CONFIG or template at $_AGENT_TEMPLATE" >&2
    return 1
  fi
}

# Emit the default mode for a harness, or empty string if null.
_agent_harness_default() {
  local harness="$1"
  _agent_read_config | jq -r --arg h "$harness" '.harness[$h].default // ""'
}

# Return 0 if harness supports mode, else 1.
_agent_harness_supports() {
  local harness="$1" mode="$2"
  _agent_read_config \
    | jq -e --arg h "$harness" --arg m "$mode" \
        '.harness[$h].supports | index($m) != null' \
    > /dev/null
}

# Emit wire for a harness ("anthropic" or "openai").
_agent_harness_wire() {
  local harness="$1"
  _agent_read_config | jq -r --arg h "$harness" '.harness[$h].wire // empty'
}

# Emit binary name for a harness.
_agent_harness_binary() {
  local harness="$1"
  _agent_read_config | jq -r --arg h "$harness" '.harness[$h].binary // empty'
}

# Clears and populates parse results into _A_* globals.
# Usage: _agent_parse <args...>
_agent_parse() {
  _A_HARNESS=""
  _A_MODE=""
  _A_MODEL=""
  _A_SHOW=0
  _A_PASSTHROUGH=()

  local positional=()
  local saw_dashdash=0
  local a
  for a in "$@"; do
    if (( saw_dashdash )); then
      _A_PASSTHROUGH+=("$a")
      continue
    fi
    case "$a" in
      --) saw_dashdash=1 ;;
      --show) _A_SHOW=1 ;;
      -a|--account) _A_MODE="account" ;;
      -g|--gw)      _A_MODE="gw" ;;
      -l|--local)   _A_MODE="local" ;;
      -*)
        echo "agent: unknown flag: $a" >&2
        return 2
        ;;
      *)
        positional+=("$a")
        ;;
    esac
  done

  # Positional: harness [mode] [model]
  _A_HARNESS="${positional[1]:-}"
  if [[ -z "$_A_MODE" && -n "${positional[2]:-}" ]]; then
    case "${positional[2]}" in
      account|gw|local)
        _A_MODE="${positional[2]}"
        _A_MODEL="${positional[3]:-}"
        ;;
      *)
        # No mode specified positionally; second positional is the model
        _A_MODEL="${positional[2]}"
        ;;
    esac
  else
    # Mode was set via flag; model is at positional[2] (or [3] if mode ate one)
    _A_MODEL="${positional[2]:-}"
    [[ -z "$_A_MODEL" ]] && _A_MODEL="${positional[3]:-}"
  fi
}

# Fetch a 1Password item. Prefers a service-account token from macOS Keychain
# (non-interactive, no app required); falls back to 1Password app integration
# (uses the desktop app's unlocked session).
_agent_op_read() {
  # NOTE: local variable must not be named `path` — in zsh it's tied to the
  # PATH array, so `local path=...` corrupts command lookup for the function.
  local ref="$1" token
  token="$(security find-generic-password -s op-service-account -a token -w 2>/dev/null)"
  if [[ -n "$token" ]]; then
    OP_SERVICE_ACCOUNT_TOKEN="$token" op read "$ref"
  else
    op read "$ref"
  fi
}

# Emit active.<slot>
_agent_active() {
  local slot="$1"
  _agent_read_config | jq -r --arg s "$slot" '.active[$s] // empty'
}

# After _agent_parse, if mode is empty, fill from harness default.
# Returns 1 if still empty after fallback.
_agent_resolve_mode() {
  if [[ -z "$_A_MODE" ]]; then
    _A_MODE="$(_agent_harness_default "$_A_HARNESS")"
  fi
  if [[ -z "$_A_MODE" ]]; then
    return 1
  fi
  return 0
}

agent() {
  # Subcommand routing (config, init, help) — stub for now, filled in a later task
  case "${1:-}" in
    config|init|help|--help|-h)
      _agent_subcommand "$@"
      return $?
      ;;
  esac

  _agent_parse "$@" || return $?

  if [[ -z "$_A_HARNESS" ]]; then
    echo "usage: agent <harness> [<mode>] [<model>] [-- <args>...]" >&2
    return 2
  fi

  if ! _agent_read_config | jq -e --arg h "$_A_HARNESS" '.harness[$h]' > /dev/null; then
    _agent_err_unknown_harness "$_A_HARNESS"
    return 2
  fi

  if ! _agent_resolve_mode; then
    _agent_err_no_default "$_A_HARNESS"
    return 2
  fi

  if ! _agent_harness_supports "$_A_HARNESS" "$_A_MODE"; then
    _agent_err_unsupported_mode "$_A_HARNESS" "$_A_MODE"
    return 2
  fi

  case "$_A_MODE" in
    account) _agent_do_account ;;
    local)   _agent_do_local ;;
    gw)      _agent_do_gw ;;
    *)
      echo "agent: internal error: unknown mode '$_A_MODE'" >&2
      return 3
      ;;
  esac
}

_agent_do_account() {
  local binary
  binary="$(_agent_harness_binary "$_A_HARNESS")"
  if (( _A_SHOW )); then
    echo "unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY"
    echo "exec $binary ${_A_PASSTHROUGH[@]}"
    return 0
  fi
  ( unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
    exec "$binary" "${_A_PASSTHROUGH[@]}" )
}

_agent_do_local() {
  if [[ -z "$_A_MODEL" ]]; then
    echo "agent: mode 'local' requires a model ID" >&2
    echo "    agent $_A_HARNESS local qwen3.6" >&2
    return 2
  fi

  local launcher
  launcher="$(_agent_read_config | jq -r --arg n "$(_agent_active local)" '.local[$n].launcher')"
  if [[ -z "$launcher" || "$launcher" == "null" ]]; then
    echo "agent: no launcher configured for active.local" >&2
    return 2
  fi

  # Build command: <launcher> <harness> --model <M> [-- <passthrough>]
  local cmd=(${=launcher} "$_A_HARNESS" --model "$_A_MODEL")
  if (( ${#_A_PASSTHROUGH[@]} > 0 )); then
    cmd+=(--)
    cmd+=("${_A_PASSTHROUGH[@]}")
  fi

  if (( _A_SHOW )); then
    echo "exec ${cmd[@]}"
    return 0
  fi
  ( exec "${cmd[@]}" )
}

_agent_do_gw() {
  if [[ -z "$_A_MODEL" ]]; then
    echo "agent: mode 'gw' requires a model ID" >&2
    echo "    agent $_A_HARNESS gw <model-id>" >&2
    return 2
  fi

  local gw_name key_ref key wire
  gw_name="$(_agent_active gateway)"
  if [[ -z "$gw_name" ]]; then
    echo "agent: no active.gateway configured" >&2
    return 2
  fi

  key_ref="$(_agent_read_config | jq -r --arg n "$gw_name" '.gateway[$n].key_ref // empty')"
  if [[ -z "$key_ref" ]]; then
    echo "agent: gateway '$gw_name' has no key_ref" >&2
    return 2
  fi

  if ! key=$(_agent_op_read "$key_ref" 2>/dev/null); then
    echo "agent: failed to read key from 1Password ($key_ref)" >&2
    echo "    - service-account auth: store token via 'security add-generic-password -s op-service-account -a token -w <ops_...> -U'" >&2
    echo "    - app-integration auth: ensure 1Password app is unlocked and CLI integration is enabled" >&2
    return 2
  fi

  wire="$(_agent_harness_wire "$_A_HARNESS")"
  case "$wire" in
    anthropic) _agent_do_gw_anthropic "$gw_name" "$key" ;;
    openai)    _agent_do_gw_openai    "$gw_name" "$key" ;;
    *)
      echo "agent: harness '$_A_HARNESS' has unknown wire '$wire'" >&2
      return 3
      ;;
  esac
}

_agent_do_gw_anthropic() {
  local gw_name="$1" key="$2" base_url binary
  base_url="$(_agent_read_config | jq -r --arg n "$gw_name" '.gateway[$n].anthropic_wire.base_url // empty')"
  if [[ -z "$base_url" ]]; then
    echo "agent: gateway '$gw_name' has no anthropic_wire.base_url" >&2
    return 2
  fi
  binary="$(_agent_harness_binary "$_A_HARNESS")"

  if (( _A_SHOW )); then
    echo "export ANTHROPIC_BASE_URL=\"$base_url\""
    echo "export ANTHROPIC_AUTH_TOKEN=\"$key\""
    echo "export ANTHROPIC_API_KEY=\"\""
    echo "exec $binary --model $_A_MODEL ${_A_PASSTHROUGH[@]}"
    return 0
  fi

  ( export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$key"
    export ANTHROPIC_API_KEY=""
    exec "$binary" --model "$_A_MODEL" "${_A_PASSTHROUGH[@]}" )
}

_agent_do_gw_openai() {
  local gw_name="$1" key="$2" binary
  binary="$(_agent_harness_binary "$_A_HARNESS")"

  if (( _A_SHOW )); then
    echo "exec $binary --provider $gw_name --model $_A_MODEL --api-key $key ${_A_PASSTHROUGH[@]}"
    return 0
  fi
  ( exec "$binary" --provider "$gw_name" --model "$_A_MODEL" --api-key "$key" "${_A_PASSTHROUGH[@]}" )
}

_agent_err_unknown_harness() {
  local bad="$1" known
  known="$(_agent_read_config | jq -r '.harness | keys | join(", ")')"
  echo "agent: unknown harness '$bad'" >&2
  echo "    known harnesses: $known" >&2
  echo "    add one in $_AGENT_CONFIG under 'harness'" >&2
}

_agent_err_no_default() {
  local harness="$1" supported
  supported="$(_agent_read_config | jq -r --arg h "$harness" '.harness[$h].supports | join(", ")')"
  echo "agent: $harness has no default mode. specify one of: $supported" >&2
  echo "    supported modes: $supported" >&2
}

_agent_err_unsupported_mode() {
  local harness="$1" mode="$2" supported
  supported="$(_agent_read_config | jq -r --arg h "$harness" '.harness[$h].supports | join(", ")')"
  echo "agent: '$mode' is not supported by harness '$harness'" >&2
  echo "    supported modes: $supported" >&2
}

_agent_subcommand() {
  case "$1" in
    --help|-h|help) _agent_help ;;
    config)
      shift
      _agent_config_subcommand "$@"
      ;;
    init)
      shift
      _agent_config_subcommand init "$@"
      ;;
    *)
      echo "agent: unknown subcommand '$1'" >&2
      return 2
      ;;
  esac
}

_agent_help() {
  cat <<'EOF'
usage: agent <harness> [<mode>] [<model>] [-- <passthrough args>...]

Modes:
  account | -a    Harness-managed subscription (claude only, default)
  gw      | -g    Via a configured gateway (uses active.gateway from config)
  local   | -l    Local model via Ollama

Subcommands:
  agent --help
  agent config                  Print resolved config
  agent config edit             $EDITOR on config.json
  agent config init             Seed config.json from template
  <any command> --show          Dry-run; print env + exec line, don't execute

Examples:
  agent claude
  agent claude gw anthropic/claude-sonnet-4.5
  agent claude local qwen3.6 -- -p "hello"
  agent pi gw openai/gpt-4o
  agent pi local qwen3.6
EOF
}

_agent_config_subcommand() {
  case "${1:-print}" in
    print|"")
      _agent_read_config | jq .
      ;;
    edit)
      ${EDITOR:-vi} "$_AGENT_CONFIG"
      ;;
    init)
      local target="${AGENT_CONFIG:-$_AGENT_CONFIG}"
      if [[ -f "$target" ]]; then
        echo "agent: $target already exists; refusing to overwrite" >&2
        return 2
      fi
      mkdir -p "$(dirname "$target")"
      cp "$_AGENT_TEMPLATE" "$target"
      echo "wrote $target"
      ;;
    *)
      echo "agent: unknown config subcommand '$1'" >&2
      return 2
      ;;
  esac
}
