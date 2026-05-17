#!/usr/bin/env zsh
# harn: unified launcher for AI coding harnesses.

# Paths: config lives under XDG (clone the repo anywhere); template ships with the repo.
# HARN_CONFIG overrides config path (used by tests).
_HARN_CONFIG="${HARN_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/harn/config.json}"
_HARN_TEMPLATE="${0:A:h}/config.template.json"

# Emit the raw config JSON. Respects $HARN_CONFIG override for tests;
# falls back to template if live config does not yet exist, so helpers
# are usable pre-`init`.
_harn_read_config() {
  if [[ -r "$_HARN_CONFIG" ]]; then
    cat "$_HARN_CONFIG"
  elif [[ -r "$_HARN_TEMPLATE" ]]; then
    cat "$_HARN_TEMPLATE"
  else
    echo "error: no config at $_HARN_CONFIG or template at $_HARN_TEMPLATE" >&2
    return 1
  fi
}

# Emit the default mode for a harness, or empty string if null.
_harn_harness_default() {
  local harness="$1"
  _harn_read_config | jq -r --arg h "$harness" '.harness[$h].default // ""'
}

# Return 0 if harness supports mode, else 1.
_harn_harness_supports() {
  local harness="$1" mode="$2"
  _harn_read_config \
    | jq -e --arg h "$harness" --arg m "$mode" \
        '.harness[$h].supports | index($m) != null' \
    > /dev/null
}

# Emit wire for a harness ("anthropic" or "openai").
_harn_harness_wire() {
  local harness="$1"
  _harn_read_config | jq -r --arg h "$harness" '.harness[$h].wire // empty'
}

# Emit binary name for a harness.
_harn_harness_binary() {
  local harness="$1"
  _harn_read_config | jq -r --arg h "$harness" '.harness[$h].binary // empty'
}

# Emit harness.<h>.gw_argv as newline-separated tokens. If absent, emit the
# default openai-wire template (pi-compatible) so existing configs keep working.
# Callers fill an array via:  argv=("${(@f)$(_harn_harness_gw_argv $h)}")
_harn_harness_gw_argv() {
  local harness="$1"
  _harn_read_config | jq -r --arg h "$harness" '
    .harness[$h].gw_argv
    // ["--provider", "{gw}", "--model", "{model}"]
    | .[]
  '
}

# Clears and populates parse results into _A_* globals.
# Usage: _harn_parse <args...>
_harn_parse() {
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
        echo "harn: unknown flag: $a" >&2
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

# Resolve a key_ref of the form `<scheme>://<rest>` by dispatching to the
# command from secrets.<scheme>.command in the config. The full key_ref is
# passed as the command's argument; stdout is the secret. The wrapper has
# no opinions about secret stores — provider config does all the work.
_harn_resolve_key() {
  local ref="$1" scheme cmd
  scheme="${ref%%://*}"
  if [[ "$scheme" == "$ref" ]]; then
    echo "harn: key_ref '$ref' has no scheme (expected <scheme>://<rest>)" >&2
    return 2
  fi
  cmd="$(_harn_read_config | jq -r --arg s "$scheme" '.secrets[$s].command // empty')"
  if [[ -z "$cmd" ]]; then
    echo "harn: no secrets provider for scheme '$scheme'" >&2
    echo "    add one in config under 'secrets.$scheme'" >&2
    return 2
  fi
  ${=cmd} "$ref"
}

# Emit active.<slot>
_harn_active() {
  local slot="$1"
  _harn_read_config | jq -r --arg s "$slot" '.active[$s] // empty'
}

# After _harn_parse, if mode is empty, fill from harness default.
# Returns 1 if still empty after fallback.
_harn_resolve_mode() {
  if [[ -z "$_A_MODE" ]]; then
    _A_MODE="$(_harn_harness_default "$_A_HARNESS")"
  fi
  if [[ -z "$_A_MODE" ]]; then
    return 1
  fi
  return 0
}

harn() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "harn: requires jq (install with: brew install jq)" >&2
    return 127
  fi

  # Subcommand routing (config, init, help) — stub for now, filled in a later task
  case "${1:-}" in
    config|init|help|--help|-h)
      _harn_subcommand "$@"
      return $?
      ;;
  esac

  _harn_parse "$@" || return $?

  if [[ -z "$_A_HARNESS" ]]; then
    echo "usage: harn <harness> [<mode>] [<model>] [-- <args>...]" >&2
    return 2
  fi

  if ! _harn_read_config | jq -e --arg h "$_A_HARNESS" '.harness[$h]' > /dev/null; then
    _harn_err_unknown_harness "$_A_HARNESS"
    return 2
  fi

  if ! _harn_resolve_mode; then
    _harn_err_no_default "$_A_HARNESS"
    return 2
  fi

  if ! _harn_harness_supports "$_A_HARNESS" "$_A_MODE"; then
    _harn_err_unsupported_mode "$_A_HARNESS" "$_A_MODE"
    return 2
  fi

  case "$_A_MODE" in
    account) _harn_do_account ;;
    local)   _harn_do_local ;;
    gw)      _harn_do_gw ;;
    *)
      echo "harn: internal error: unknown mode '$_A_MODE'" >&2
      return 3
      ;;
  esac
}

_harn_do_account() {
  local binary wire
  binary="$(_harn_harness_binary "$_A_HARNESS")"
  wire="$(_harn_harness_wire "$_A_HARNESS")"

  # Pick env vars to clear so account-mode auth (subscription/login) is not
  # silently overridden by a stray API key or base URL in the user's shell.
  local -a clear
  case "$wire" in
    anthropic) clear=(ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY) ;;
    openai)    clear=(OPENAI_API_KEY OPENAI_BASE_URL) ;;
    *)
      echo "harn: harness '$_A_HARNESS' has unknown wire '$wire'" >&2
      return 3
      ;;
  esac

  if (( _A_SHOW )); then
    echo "unset ${clear[*]}"
    echo "exec ${(q-)binary} ${(q-)_A_PASSTHROUGH[@]}"
    return 0
  fi
  ( unset "${clear[@]}"
    exec "$binary" "${_A_PASSTHROUGH[@]}" )
}

_harn_do_local() {
  if [[ -z "$_A_MODEL" ]]; then
    echo "harn: mode 'local' requires a model ID" >&2
    echo "    harn $_A_HARNESS local qwen3.6" >&2
    return 2
  fi

  local launcher
  launcher="$(_harn_read_config | jq -r --arg n "$(_harn_active local)" '.local[$n].launcher')"
  if [[ -z "$launcher" || "$launcher" == "null" ]]; then
    echo "harn: no launcher configured for active.local" >&2
    return 2
  fi

  # Build command: <launcher> <harness> --model <M> [-- <passthrough>]
  local cmd=(${=launcher} "$_A_HARNESS" --model "$_A_MODEL")
  if (( ${#_A_PASSTHROUGH[@]} > 0 )); then
    cmd+=(--)
    cmd+=("${_A_PASSTHROUGH[@]}")
  fi

  if (( _A_SHOW )); then
    echo "exec ${(q-)cmd[@]}"
    return 0
  fi
  ( exec "${cmd[@]}" )
}

_harn_do_gw() {
  if [[ -z "$_A_MODEL" ]]; then
    echo "harn: mode 'gw' requires a model ID" >&2
    echo "    harn $_A_HARNESS gw <model-id>" >&2
    return 2
  fi

  local gw_name key_ref key wire
  gw_name="$(_harn_active gateway)"
  if [[ -z "$gw_name" ]]; then
    echo "harn: no active.gateway configured" >&2
    return 2
  fi

  key_ref="$(_harn_read_config | jq -r --arg n "$gw_name" '.gateway[$n].key_ref // empty')"
  if [[ -z "$key_ref" ]]; then
    echo "harn: gateway '$gw_name' has no key_ref" >&2
    return 2
  fi

  if ! key=$(_harn_resolve_key "$key_ref"); then
    echo "harn: failed to resolve key_ref '$key_ref'" >&2
    return 2
  fi

  wire="$(_harn_harness_wire "$_A_HARNESS")"
  case "$wire" in
    anthropic) _harn_do_gw_anthropic "$gw_name" "$key" ;;
    openai)    _harn_do_gw_openai    "$gw_name" "$key" ;;
    *)
      echo "harn: harness '$_A_HARNESS' has unknown wire '$wire'" >&2
      return 3
      ;;
  esac
}

_harn_do_gw_anthropic() {
  local gw_name="$1" key="$2" base_url binary
  base_url="$(_harn_read_config | jq -r --arg n "$gw_name" '.gateway[$n].anthropic_wire.base_url // empty')"
  if [[ -z "$base_url" ]]; then
    echo "harn: gateway '$gw_name' has no anthropic_wire.base_url" >&2
    return 2
  fi
  binary="$(_harn_harness_binary "$_A_HARNESS")"

  if (( _A_SHOW )); then
    echo "export ANTHROPIC_BASE_URL=${(qqq)base_url}"
    echo "export ANTHROPIC_AUTH_TOKEN=${(qqq)key}"
    echo "export ANTHROPIC_API_KEY=\"\""
    echo "exec ${(q-)binary} --model ${(q-)_A_MODEL} ${(q-)_A_PASSTHROUGH[@]}"
    return 0
  fi

  ( export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$key"
    export ANTHROPIC_API_KEY=""
    exec "$binary" --model "$_A_MODEL" "${_A_PASSTHROUGH[@]}" )
}

_harn_do_gw_openai() {
  local gw_name="$1" key="$2" binary key_env
  binary="$(_harn_harness_binary "$_A_HARNESS")"

  # Pick env-var name: explicit gateway.key_env, else <UPPER(gw_name)>_API_KEY.
  # Avoids putting the key on argv (visible in `ps`).
  key_env="$(_harn_read_config | jq -r --arg n "$gw_name" '.gateway[$n].key_env // empty')"
  [[ -z "$key_env" ]] && key_env="${(U)gw_name}_API_KEY"

  # Build templated argv from harness.<h>.gw_argv. Each openai-wire harness
  # spells "use gateway X with model Y" differently (pi has --provider, codex
  # has -c model_provider=...), so the shape lives in config.
  local -a argv tmpl
  tmpl=("${(@f)$(_harn_harness_gw_argv "$_A_HARNESS")}")
  local tok
  for tok in "${tmpl[@]}"; do
    tok="${tok//\{gw\}/$gw_name}"
    tok="${tok//\{model\}/$_A_MODEL}"
    argv+=("$tok")
  done

  if (( _A_SHOW )); then
    echo "export ${key_env}=${(qqq)key}"
    echo "exec ${(q-)binary} ${(q-)argv[@]} ${(q-)_A_PASSTHROUGH[@]}"
    return 0
  fi
  ( export "$key_env=$key"
    exec "$binary" "${argv[@]}" "${_A_PASSTHROUGH[@]}" )
}

_harn_err_unknown_harness() {
  local bad="$1" known
  known="$(_harn_read_config | jq -r '.harness | keys | join(", ")')"
  echo "harn: unknown harness '$bad'" >&2
  echo "    known harnesses: $known" >&2
  echo "    add one in $_HARN_CONFIG under 'harness'" >&2
}

_harn_err_no_default() {
  local harness="$1" supported
  supported="$(_harn_read_config | jq -r --arg h "$harness" '.harness[$h].supports | join(", ")')"
  echo "harn: $harness has no default mode. specify one of: $supported" >&2
  echo "    supported modes: $supported" >&2
}

_harn_err_unsupported_mode() {
  local harness="$1" mode="$2" supported
  supported="$(_harn_read_config | jq -r --arg h "$harness" '.harness[$h].supports | join(", ")')"
  echo "harn: '$mode' is not supported by harness '$harness'" >&2
  echo "    supported modes: $supported" >&2
}

_harn_subcommand() {
  case "$1" in
    --help|-h|help) _harn_help ;;
    config)
      shift
      _harn_config_subcommand "$@"
      ;;
    init)
      shift
      _harn_config_subcommand init "$@"
      ;;
    *)
      echo "harn: unknown subcommand '$1'" >&2
      return 2
      ;;
  esac
}

_harn_help() {
  cat <<'EOF'
usage: harn <harness> [<mode>] [<model>] [-- <passthrough args>...]

Modes:
  account | -a    Harness-managed subscription (claude, codex)
  gw      | -g    Via a configured gateway (uses active.gateway from config)
  local   | -l    Local model via configured launcher (default: ollama launch)

Subcommands:
  harn --help
  harn config                  Print resolved config
  harn config edit             $EDITOR on config.json
  harn config init             Seed config.json from template
  <any command> --show          Dry-run; print env + exec line, don't execute

Examples:
  harn claude
  harn claude gw anthropic/claude-sonnet-4.5
  harn claude local qwen3.6 -- -p "hello"
  harn codex
  harn codex gw openai/gpt-4o
  harn pi gw openai/gpt-4o
  harn pi local qwen3.6
EOF
}

_harn_config_subcommand() {
  case "${1:-print}" in
    print|"")
      _harn_read_config | jq .
      ;;
    edit)
      ${EDITOR:-vi} "$_HARN_CONFIG"
      ;;
    init)
      local target="${HARN_CONFIG:-$_HARN_CONFIG}"
      if [[ -f "$target" ]]; then
        echo "harn: $target already exists; refusing to overwrite" >&2
        return 2
      fi
      mkdir -p "$(dirname "$target")"
      cp "$_HARN_TEMPLATE" "$target"
      echo "wrote $target"
      ;;
    *)
      echo "harn: unknown config subcommand '$1'" >&2
      return 2
      ;;
  esac
}
