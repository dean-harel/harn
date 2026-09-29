# harn 0.1: Providers, Credentials and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sourced zsh function with a released `bin/harn` executable that runs any harness against a subscription, a gateway API or a local model, with credentials handled.

**Architecture:** One bash 3.2 script, `bin/harn`, reads a JSON config with `jq`. A run resolves a source (the subscription, a slot or a named provider) to one of three kinds (`account`, `endpoint`, `launcher`), builds an environment and an argv, and either prints them (`--show`) or execs. Credentials come from a login (`openrouter-pkce`, `paste`) that stores the key in a 0600 file, or from a `key_command`.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), `jq`, `curl`, `openssl`; GitHub Actions; release-please; the repository as its own Homebrew tap.

**Spec:** `.agents/specs/2026-09-28-providers-and-release-design.md`

## Global Constraints

- Scripts run under macOS `/bin/bash` 3.2: no `mapfile`, no associative arrays, empty arrays expanded as `${a[@]+"${a[@]}"}` under `set -u`.
- Dependencies are `jq`, `curl` and `openssl`, checked before first use; a missing one exits 2 naming the install command.
- Exit codes: 2 for a usage or config error, 3 for an internal error, otherwise the harness's own. Every error names the field or command to fix.
- A key reaches a harness only through its environment: never argv, never written outside the store, never printed except by `harn key`. `--show` never resolves a credential.
- Every command-shaped config field (`launcher`, `key_command`) is an argv array.
- Nothing in the test suite launches a real harness or reaches the network.
- Conventional Commits; no attribution trailers; ASCII only in files.
- Work happens on branch `feat/providers` in `~/Developer/personal/harn`. Pushing, opening a PR and merging a release PR are outward acts: stop and ask before each.
- The first release is 0.1.0. The slot object form and `harness_names` are built only if Task 1 answers no to the spec's verify-first item 1 or 2.

## Review Focus

1. A passthrough argument with spaces, quotes or an empty string survives both the real exec and the `--show` line when that line is pasted into a shell. Pinned in Task 2.
2. A `key_command` argument containing a space reaches the command as one argument. Pinned in Task 3.
3. A user whose live config is still the legacy schema (`active`, `gateway`, no `providers`) gets an exit 2 pointing at the migration, never a `jq` error. Pinned in Task 2.
4. A pasted key comes back from the store byte for byte, with no added newline, and the file is mode 0600. Pinned in Task 5.
5. `harn` run through a symlink (the Homebrew layout) still finds `lib/config.template.json`. Pinned in Task 7.

## File Structure

- `bin/harn`: the whole tool. Sections in order: header and version, messages, paths, config, parsing, sources, kinds, credentials, key store, logins, run, subcommands, main.
- `lib/config.template.json`: the shipped template, rewritten to the 0.1 schema.
- `lib/harn.zsh`: reduced to a stub that tells an old install what to change.
- `tests/lib.sh`: assertion helpers and an isolated `HOME`.
- `tests/run.sh`: runs every `tests/t_*.sh` and prints the tally.
- `tests/t_account.sh`, `tests/t_endpoint.sh`, `tests/t_launcher.sh`, `tests/t_store.sh`, `tests/t_pkce.sh`, `tests/t_config.sh`: one file per area.
- `tests/dry-run.sh`: deleted in Task 2; its cases are rewritten across the task files.
- `.github/workflows/ci.yml`, `.github/workflows/pr-title.yml`, `.github/workflows/release.yml`.
- `release-please-config.json`, `.release-please-manifest.json`.
- `Formula/harn.rb`: the Homebrew formula; the repository is its own tap.
- `README.md`, `AGENTS.md` (with `CLAUDE.md` symlink), `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/bug.yml`, `.github/ISSUE_TEMPLATE/feature.yml`.

---

### Task 1: Settle the two local unknowns

The spec's "Verify first" items 1 and 2 decide parts of Tasks 2 to 4, so they are answered before any code.

**Files:**
- Modify: `.agents/specs/2026-09-28-providers-and-release-design.md` ("Verify first")

**Interfaces:**
- Produces: two recorded answers that Tasks 2, 3 and 4 read: `LAUNCH_PI_HERMES` (yes or no), `PI_HERMES_BASE_URL` (the flag, or no).

- [ ] **Step 1: Create the branch**

```bash
cd ~/Developer/personal/harn && git switch -c feat/providers
```
Expected: `Switched to a new branch 'feat/providers'`

- [ ] **Step 2: Item 1, does `ollama launch` support pi and hermes**

```bash
ollama --version; ollama launch --help 2>&1 | sed -n '1,60p'
```
Expected: a list of supported integrations. Record `LAUNCH_PI_HERMES=yes` only if both `pi` and `hermes` appear.

- [ ] **Step 3: Item 2, can pi and hermes take a base URL from argv**

```bash
pi --help 2>&1 | grep -n -i -E 'base.?url|provider|api.?key|models' ; hermes chat --help 2>&1 | grep -n -i -E 'base.?url|provider|api.?key'
```
Expected: flag lines. Record `PI_HERMES_BASE_URL` as the exact flag per harness (for example `pi: --base-url`) or `no`.

- [ ] **Step 4: Record the answers in the spec**

Replace items 1 and 2 of "Verify first" with the settled answers, each as one sentence plus the consequence the spec already names. Example for a yes on item 2:

```markdown
2. Settled: pi takes `--base-url` and hermes takes `--base-url` after `chat`, so both `gw_argv`
   carry `{base_url}` and swap to any provider; `harness_names` is not built.
```

For a no on item 1, also add the `ollama-api` provider and the object-valued `slots.local` to the spec's template block, and move the slot object form from verify-first item 1 into the Config section's Slots bullet. For a no on item 2, move `harness_names` into the Config section the same way.

- [ ] **Step 5: Commit**

```bash
git add .agents/specs/2026-09-28-providers-and-release-design.md
git commit -m "docs(spec): settle the local verify-first items"
```

---

### Task 2: Walking skeleton: `bin/harn` with the subscription path, `--show` and CI

Ends with `harn claude --show` and `harn claude` (against a stub) working from the new executable on macOS `/bin/bash`, and the suite wired into CI for both platforms.

**Files:**
- Create: `bin/harn`, `tests/lib.sh`, `tests/run.sh`, `tests/t_account.sh`, `.github/workflows/ci.yml`, `.github/workflows/pr-title.yml`
- Modify: `lib/config.template.json` (rewrite)
- Delete: `tests/dry-run.sh`

**Interfaces:**
- Produces, in `bin/harn`:
  - `harn_die CODE MESSAGE [HINT...]`: prints `harn: MESSAGE` and indented hints to stderr, exits CODE.
  - `harn_warn MESSAGE`
  - `harn_require TOOL...`
  - `cfg JQ_ARGS...`: runs `jq -r` over the loaded config (`$HARN_CFG`).
  - Globals after parsing: `A_HARNESS`, `A_SOURCE`, `A_MODEL`, `A_SHOW` (0 or 1), array `A_PASS`.
  - Globals after source resolution: `S_PROVIDER` (empty for the subscription), `S_KIND` (`account`, `endpoint`, `launcher`), `S_LABEL`.
  - `harn_pfield JQ_PATH`: a field of the resolved provider, empty when absent.
  - `harn_harness_field NAME`
  - Run plan: arrays `E_NAMES`, `E_VALUES`, `E_SHOWN`, `X_ARGV`; `harn_setenv NAME VALUE [SHOWN]`; `harn_run`.
  - `harn_clean_vars`: prints every variable a run unsets, one per line, sorted and unique.
  - `harn_key_env WIRE PROVIDER`
- Produces, in `tests/lib.sh`: `run ARGS...` (sets `OUT`, `RC`), `has NAME HAYSTACK NEEDLE`, `lacks NAME HAYSTACK NEEDLE`, `code NAME GOT WANT`, `cfgwith JQ_FILTER` (prints a temp config path), `stub NAME SCRIPT` (writes an executable into `$STUBS`), `$ROOT`, `$STUBS`.

- [ ] **Step 1: Rewrite the template to the 0.1 schema**

`lib/config.template.json`:

```json
{
  "slots": { "gw": "openrouter", "local": "ollama" },
  "providers": {
    "openrouter": {
      "kind": "endpoint",
      "label": "api",
      "login": "openrouter-pkce",
      "default_model": "anthropic/claude-sonnet-5",
      "anthropic_wire": { "base_url": "https://openrouter.ai/api" },
      "openai_wire": { "base_url": "https://openrouter.ai/api/v1", "wire_api": "responses" }
    },
    "ollama-cloud": {
      "kind": "endpoint",
      "label": "api",
      "login": "paste",
      "default_model": "glm-5.3-flash",
      "anthropic_wire": { "base_url": "https://ollama.com" },
      "openai_wire": { "base_url": "https://ollama.com/v1", "wire_api": "responses" }
    },
    "anthropic": {
      "kind": "endpoint",
      "label": "api",
      "login": "paste",
      "default_model": "claude-sonnet-5",
      "anthropic_wire": { "base_url": "https://api.anthropic.com", "key_env": "ANTHROPIC_API_KEY" }
    },
    "ollama": { "kind": "launcher", "label": "local", "launcher": ["ollama", "launch"] }
  },
  "harness": {
    "claude": { "wire": "anthropic", "binary": "claude", "account": true },
    "codex": {
      "wire": "openai", "binary": "codex", "account": true,
      "gw_argv": [
        "-c", "model_providers.{provider}.name={provider}",
        "-c", "model_providers.{provider}.base_url={base_url}",
        "-c", "model_providers.{provider}.env_key={key_env}",
        "-c", "model_providers.{provider}.wire_api={wire_api}",
        "-c", "model_provider={provider}",
        "--model", "{model}"
      ]
    },
    "pi": { "wire": "openai", "binary": "pi", "gw_argv": ["--provider", "{provider}", "--model", "{model}"] },
    "hermes": { "wire": "openai", "binary": "hermes", "gw_argv": ["chat", "--provider", "{provider}", "--model", "{model}"] }
  }
}
```

Apply Task 1's answers: with `LAUNCH_PI_HERMES=no`, add the `ollama-api` provider and the object-valued `slots.local` from the spec, and in Step 5 use the object-aware slot lookup below; with a `PI_HERMES_BASE_URL` flag, add `"<flag>", "{base_url}"` to that harness's `gw_argv`.

Object-aware slot lookup, only for `LAUNCH_PI_HERMES=no` (it replaces the `gw|local)` branch of `harn_resolve_source`, and the "object slot is a config error" test is replaced by the two "slot object" tests shown in Task 3):

```bash
    gw|local)
      S_PROVIDER=$(cfg --arg s "$A_SOURCE" --arg h "$A_HARNESS" \
        '.slots[$s] // empty | if type == "object" then (.[$h] // .["*"] // empty) else . end')
      [ -n "$S_PROVIDER" ] || harn_die 2 "slot '$A_SOURCE' has no provider for $A_HARNESS" "set slots.$A_SOURCE in $HARN_CONFIG_PATH"
      ;;
```

- [ ] **Step 2: Write the test helpers**

`tests/lib.sh`:

```bash
# Sourced by tests/run.sh. Every test runs bin/harn as a child process against an isolated HOME.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HARN="$ROOT/bin/harn"
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
run()   { OUT=$("$HARN" "$@" 2>&1); RC=$?; }
cfgwith() { local f; f=$(mktemp); jq "$1" "$ROOT/lib/config.template.json" > "$f"; printf '%s' "$f"; }
stub()  { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
```

`tests/run.sh`:

```bash
#!/bin/bash
# Runs the suite under whatever bash invokes it; CI uses /bin/bash on macOS for 3.2.
set -u
. "$(dirname "$0")/lib.sh"
for t in "$ROOT"/tests/t_*.sh; do
  . "$t"
done
printf '%d passed, %d failed\n' "$T_PASS" "$T_FAIL"
[ "$T_FAIL" = 0 ]
```

- [ ] **Step 3: Write the failing subscription-path tests**

`tests/t_account.sh`:

```bash
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

# Review Focus 3: a legacy config exits 2 with the migration pointer.
old=$(mktemp)
printf '{"active":{"gateway":"openrouter"},"gateway":{},"harness":{}}' > "$old"
OUT=$(HARN_CONFIG="$old" "$HARN" claude --show 2>&1); RC=$?
code "legacy config is a config error" "$RC" 2
has "legacy config names the migration" "$OUT" "uses the legacy schema"

# A slot must name one provider (the object form is built only after a no on verify-first item 1).
OUT=$(HARN_CONFIG=$(cfgwith '.slots.gw = {"*": "openrouter"}') "$HARN" claude gw --show 2>&1); RC=$?
code "object slot is a config error" "$RC" 2
has "object slot names the field" "$OUT" "slots.gw must be a provider name"

# Reserved provider names.
OUT=$(HARN_CONFIG=$(cfgwith '.providers.gw = .providers.openrouter') "$HARN" claude --show 2>&1); RC=$?
code "reserved provider name" "$RC" 2
has "reserved name message" "$OUT" "provider name 'gw' is reserved"
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `/bin/bash tests/run.sh`
Expected: FAIL lines, starting with `version exits 0`, because `bin/harn` does not exist.

- [ ] **Step 5: Write the skeleton**

`bin/harn`:

```bash
#!/bin/bash
# harn: one command for any AI coding harness, against a subscription, a gateway or a local model.
# Must run under macOS /bin/bash 3.2: no mapfile, no associative arrays, empty arrays as ${a[@]+"${a[@]}"}.
set -u

HARN_VERSION="0.0.0-dev" # x-release-please-version

# --- messages

harn_die() {
  local code=$1 first=$2
  shift 2
  printf 'harn: %s\n' "$first" >&2
  [ $# -eq 0 ] || printf '    %s\n' "$@" >&2
  exit "$code"
}

harn_warn() { printf 'harn: warning: %s\n' "$1" >&2; }

harn_require() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 \
      || harn_die 2 "requires $t" "install it: brew install $t, or your Linux package manager"
  done
}

# --- paths

harn_self_dir() {
  local p=$0 d
  while [ -L "$p" ]; do
    d=$(cd -P "$(dirname "$p")" && pwd)
    p=$(readlink "$p")
    case $p in /*) ;; *) p="$d/$p" ;; esac
  done
  cd -P "$(dirname "$p")" && pwd
}

HARN_ROOT=$(cd "$(harn_self_dir)/.." && pwd)
HARN_TEMPLATE="$HARN_ROOT/lib/config.template.json"
HARN_CONFIG_PATH="${HARN_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/harn/config.json}"

# --- config

harn_load_config() {
  local src=$HARN_CONFIG_PATH bad
  [ -r "$src" ] || src=$HARN_TEMPLATE
  HARN_CFG=$(cat "$src") || harn_die 2 "cannot read $src"
  jq -e . >/dev/null 2>&1 <<<"$HARN_CFG" || harn_die 2 "$src is not valid JSON"
  if jq -e '(has("gateway") or has("active")) and (has("providers") | not)' >/dev/null <<<"$HARN_CFG"; then
    harn_die 2 "$src uses the legacy schema" "see the 0.1.0 migration in CHANGELOG.md, or back it up and run: harn config init --force"
  fi
  bad=$(jq -r '.providers // {} | keys[] | select(. == "gw" or . == "local" or . == "account")' <<<"$HARN_CFG" | head -n 1)
  [ -z "$bad" ] || harn_die 2 "provider name '$bad' is reserved" "rename providers.$bad in $src"
}

cfg() { jq -r "$@" <<<"$HARN_CFG"; }

# --- parsing

harn_usage() { printf 'usage: harn <harness> [<source>] [<model>] [--show] [-- <args>...]\n'; }

harn_parse() {
  local pos=() a
  A_HARNESS='' A_SOURCE='' A_MODEL='' A_SHOW=0
  A_PASS=()
  while [ $# -gt 0 ]; do
    a=$1
    shift
    case $a in
      --) A_PASS=("$@"); break ;;
      --show) A_SHOW=1 ;;
      -*) harn_die 2 "unknown flag: $a" "see: harn --help" ;;
      *) pos+=("$a") ;;
    esac
  done
  [ ${#pos[@]} -ge 1 ] || { harn_usage >&2; exit 2; }
  [ ${#pos[@]} -le 3 ] || harn_die 2 "too many arguments: ${pos[*]}" "$(harn_usage)"
  A_HARNESS=${pos[0]}
  A_SOURCE=${pos[1]:-}
  A_MODEL=${pos[2]:-}
}

harn_harness_field() { cfg --arg h "$A_HARNESS" --arg f "$1" '.harness[$h][$f] // empty'; }

harn_check_harness() {
  [ -n "$(harn_harness_field binary)" ] || harn_die 2 "unknown harness '$A_HARNESS'" \
    "known harnesses: $(cfg '.harness | keys | join(", ")')" "add one under 'harness' in $HARN_CONFIG_PATH"
}

# --- sources

harn_resolve_source() {
  S_PROVIDER='' S_KIND=account S_LABEL=subscription
  case $A_SOURCE in
    ''|account) ;;
    gw|local)
      [ "$(cfg --arg s "$A_SOURCE" '.slots[$s] | type')" != object ] \
        || harn_die 2 "slots.$A_SOURCE must be a provider name" "set slots.$A_SOURCE in $HARN_CONFIG_PATH"
      S_PROVIDER=$(cfg --arg s "$A_SOURCE" '.slots[$s] // empty')
      [ -n "$S_PROVIDER" ] || harn_die 2 "slot '$A_SOURCE' has no provider" "set slots.$A_SOURCE in $HARN_CONFIG_PATH"
      ;;
    *) S_PROVIDER=$A_SOURCE ;;
  esac
  if [ -n "$S_PROVIDER" ]; then
    S_KIND=$(harn_pfield .kind)
    [ -n "$S_KIND" ] || harn_die 2 "unknown source '$S_PROVIDER'" \
      "known: account, gw, local, $(cfg '.providers // {} | keys | join(", ")')"
    S_LABEL=$(harn_pfield '.label // "api"')
  elif [ "$(harn_harness_field account)" != true ]; then
    harn_die 2 "$A_HARNESS has no subscription login; use gw, local or a provider"
  fi
}

harn_pfield() { cfg --arg p "$S_PROVIDER" ".providers[\$p]$1 // empty"; }

# --- kinds

harn_kind_account() {
  X_ARGV=("$(harn_harness_field binary)")
  [ -z "$A_MODEL" ] || X_ARGV+=(--model "$A_MODEL")
  X_ARGV+=(${A_PASS[@]+"${A_PASS[@]}"})
}

# --- environment

harn_key_env() {
  local wire=$1 p=$2 explicit
  explicit=$(cfg --arg p "$p" --arg w "${wire}_wire" '.providers[$p][$w].key_env // empty')
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
  elif [ "$wire" = anthropic ]; then
    printf 'ANTHROPIC_AUTH_TOKEN\n'
  else
    printf '%s_API_KEY\n' "$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_' '_')"
  fi
}

harn_clean_vars() {
  local p
  {
    printf '%s\n' ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY OPENAI_API_KEY OPENAI_BASE_URL
    while IFS= read -r p; do
      [ "$(cfg --arg p "$p" '.providers[$p].kind')" = endpoint ] || continue
      harn_key_env anthropic "$p"
      harn_key_env openai "$p"
    done < <(cfg '.providers // {} | keys[]')
  } | sort -u
}

harn_warn_claude_settings() {
  local f
  for f in "$HOME/.claude/settings.json" .claude/settings.json .claude/settings.local.json; do
    [ -r "$f" ] || continue
    jq -e '(.env // {}) | keys | any(test("^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|OPENAI_API_KEY|OPENAI_BASE_URL)$"))' \
      "$f" >/dev/null 2>&1 && harn_warn "$f sets provider variables under env, which override this run"
  done
  return 0
}

# --- run

harn_setenv() { E_NAMES+=("$1"); E_VALUES+=("$2"); E_SHOWN+=("${3-$2}"); }

harn_q() {
  case $1 in
    '<redacted: '*) printf '%s' "$1" ;;
    *) printf '%q' "$1" ;;
  esac
}

harn_run() {
  local vars i a
  vars=$(harn_clean_vars | tr '\n' ' ')
  vars=${vars% }
  if [ "$A_SHOW" = 1 ]; then
    printf '# source: %s (%s)\n' "${S_PROVIDER:-account}" "$S_LABEL"
    printf 'unset %s\n' "$vars"
    i=0
    while [ "$i" -lt "${#E_NAMES[@]}" ]; do
      printf 'export %s=%s\n' "${E_NAMES[$i]}" "$(harn_q "${E_SHOWN[$i]}")"
      i=$((i + 1))
    done
    printf 'exec'
    for a in "${X_ARGV[@]}"; do printf ' %s' "$(harn_q "$a")"; done
    printf '\n'
    exit 0
  fi
  command -v "${X_ARGV[0]}" >/dev/null 2>&1 \
    || harn_die 2 "'${X_ARGV[0]}' is not on PATH" "install it, or fix its binary in $HARN_CONFIG_PATH"
  # shellcheck disable=SC2086 # names are identifiers; splitting is intended
  unset $vars
  i=0
  while [ "$i" -lt "${#E_NAMES[@]}" ]; do
    export "${E_NAMES[$i]}=${E_VALUES[$i]}"
    i=$((i + 1))
  done
  exec "${X_ARGV[@]}"
}

# --- main

harn_main() {
  harn_require jq
  case ${1:-} in
    --version) printf 'harn %s\n' "$HARN_VERSION"; exit 0 ;;
  esac
  harn_load_config
  harn_parse "$@"
  harn_check_harness
  harn_resolve_source
  E_NAMES=() E_VALUES=() E_SHOWN=() X_ARGV=()
  case $S_KIND in
    account) harn_kind_account ;;
    *) harn_die 2 "provider '$S_PROVIDER' has unknown kind '$S_KIND'" "kind is one of: endpoint, launcher" ;;
  esac
  if [ "$(harn_harness_field wire)" = anthropic ] && [ "$S_KIND" != launcher ]; then
    harn_warn_claude_settings
  fi
  harn_run
}

harn_main "$@"
```

Then `chmod +x bin/harn` and `git rm tests/dry-run.sh`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `/bin/bash tests/run.sh`
Expected: every line `PASS`, last line `N passed, 0 failed`. The `unknown source` test passes because `nowhere` is not a provider; the endpoint and launcher kinds arrive in Tasks 3 and 4.

- [ ] **Step 7: Syntax-check and run on Linux**

```bash
bash -n bin/harn && /bin/bash -n bin/harn && echo syntax-ok
docker run --rm -v "$PWD":/w -w /w ubuntu:24.04 bash -c 'apt-get update -qq && apt-get install -y -qq jq >/dev/null && bash tests/run.sh' | tail -n 3
```
Expected: `syntax-ok`, then `N passed, 0 failed` from the Ubuntu container. If Docker cannot pull, record that the Linux check moves to CI on the PR.

- [ ] **Step 8: Add CI**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Test under the platform's /bin/bash
        run: /bin/bash tests/run.sh

  shellcheck:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: shellcheck --shell=bash bin/harn tests/*.sh
```

`.github/workflows/pr-title.yml`:

```yaml
name: PR title

on:
  pull_request:
    types: [opened, edited, synchronize]

permissions: {}

jobs:
  title:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      pull-requests: read
    steps:
      - uses: amannn/action-semantic-pull-request@48f256284bd46cdaab1048c3721360e808335d50 # v6.1.1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat
            fix
            docs
            test
            refactor
            chore
            ci
```

The pins are the ones `UNIPaaS/gates` uses. `shellcheck` is preinstalled on `ubuntu-latest`; it is not installed on this machine, so the lint runs in CI.

- [ ] **Step 9: Commit**

```bash
git add bin/harn lib/config.template.json tests .github/workflows/ci.yml .github/workflows/pr-title.yml
git commit -m "feat!: ship bin/harn with the subscription path and --show"
```

---

### Task 3: Endpoint kind with `key_command`

Ends with `harn claude gw` and `harn codex gw` building the right environment and argv from a provider, with a `key_command` credential, against stub harnesses.

**Files:**
- Modify: `bin/harn` (kinds, credentials, main dispatch)
- Create: `tests/t_endpoint.sh`

**Interfaces:**
- Consumes: everything Task 2 produces.
- Produces:
  - `harn_kind_endpoint`
  - `harn_credential`: sets `C_VALUE` (empty under `--show`) and `C_SHOWN` (the redaction text).
  - `harn_key_value PROVIDER`: prints the provider's key from `key_command`, else from `harn_store_read`.
  - `harn_store_read PROVIDER`: in this task, always exits 2 with `run: harn login PROVIDER`. Task 5 replaces it.

- [ ] **Step 1: Write the failing endpoint tests**

`tests/t_endpoint.sh`:

```bash
# Endpoint kind: both wires, key variables, defaults, slots, redaction, key_command.

kc=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printf", "%s", "sk-test-1"])
  | .providers["ollama-cloud"] |= (del(.login) | .key_command = ["printf", "%s", "sk-oc-1"])')

OUT=$(HARN_CONFIG="$kc" "$HARN" claude gw --show 2>&1); RC=$?
code "claude gw --show" "$RC" 0
has "labels the gateway" "$OUT" "# source: openrouter (api)"
has "sets base url" "$OUT" "export ANTHROPIC_BASE_URL=https://openrouter.ai/api"
has "redacts key_command" "$OUT" "export ANTHROPIC_AUTH_TOKEN=<redacted: key_command printf %s sk-test-1>"
has "empties the api key" "$OUT" "export ANTHROPIC_API_KEY=''"
has "uses the default model" "$OUT" "exec claude --model anthropic/claude-sonnet-5"
lacks "--show never resolves the key" "$(printf '%s' "$OUT" | grep -v key_command)" "sk-test-1"

OUT=$(HARN_CONFIG="$kc" "$HARN" claude gw some/model --show -- -p hi 2>&1)
has "explicit model and passthrough" "$OUT" "exec claude --model some/model -p hi"

OUT=$(HARN_CONFIG="$kc" "$HARN" codex gw --show 2>&1)
has "codex key variable" "$OUT" "export OPENROUTER_API_KEY=<redacted: key_command"
has "codex provider injection" "$OUT" "model_providers.openrouter.base_url=https://openrouter.ai/api/v1"
has "codex env_key" "$OUT" "model_providers.openrouter.env_key=OPENROUTER_API_KEY"
has "codex wire_api" "$OUT" "model_providers.openrouter.wire_api=responses"

OUT=$(HARN_CONFIG="$kc" "$HARN" codex ollama-cloud --show 2>&1)
has "hyphenated provider maps to an identifier" "$OUT" "export OLLAMA_CLOUD_API_KEY="
/bin/bash -c 'export OLLAMA_CLOUD_API_KEY=x' && ok "derived name exports under /bin/bash" || bad "derived name exports under /bin/bash"

OUT=$(HARN_CONFIG="$kc" "$HARN" pi gw m --show 2>&1)
has "pi argv" "$OUT" "exec pi --provider openrouter --model m"

OUT=$(HARN_CONFIG="$kc" "$HARN" codex anthropic --show 2>&1); RC=$?
code "missing wire block" "$RC" 2
has "missing wire names the field" "$OUT" "providers.anthropic.openai_wire.base_url"

nodef=$(cfgwith 'del(.providers.openrouter.default_model) | .providers.openrouter |= (del(.login) | .key_command = ["true"])')
OUT=$(HARN_CONFIG="$nodef" "$HARN" claude gw --show 2>&1); RC=$?
code "no model and no default" "$RC" 2
has "names default_model" "$OUT" "providers.openrouter.default_model"

both=$(cfgwith '.providers.openrouter.key_command = ["true"]')
OUT=$(HARN_CONFIG="$both" "$HARN" claude gw --show 2>&1); RC=$?
code "login and key_command both set" "$RC" 2

# Slot swap, compared line by line.
a=$(HARN_CONFIG="$kc" "$HARN" claude gw --show 2>&1)
sw=$(cfgwith '.slots.gw = "ollama-cloud" | .providers.openrouter |= (del(.login) | .key_command = ["printf", "%s", "sk-test-1"]) | .providers["ollama-cloud"] |= (del(.login) | .key_command = ["printf", "%s", "sk-oc-1"])')
b=$(HARN_CONFIG="$sw" "$HARN" claude gw --show 2>&1)
has "swap: new base url" "$b" "ANTHROPIC_BASE_URL=https://ollama.com"
has "swap: same key variable" "$b" "export ANTHROPIC_AUTH_TOKEN="
has "swap: new default model" "$b" "exec claude --model glm-5.3-flash"
lacks "swap: nothing from openrouter" "$b" "openrouter"
c=$(HARN_CONFIG="$sw" "$HARN" codex gw --show 2>&1)
has "swap codex: key variable" "$c" "export OLLAMA_CLOUD_API_KEY="
has "swap codex: provider tokens" "$c" "model_provider=ollama-cloud"
lacks "swap codex: nothing from openrouter" "$c" "openrouter"

# Real exec against a stub: key in env, inherited vars cleared.
stub claude 'printf "BASE=%s TOKEN=%s APIKEY=[%s] OAI=%s\n" "$ANTHROPIC_BASE_URL" "$ANTHROPIC_AUTH_TOKEN" "$ANTHROPIC_API_KEY" "${OPENAI_BASE_URL-unset}"; printf "ARGS=%s\n" "$*"'
OUT=$(OPENAI_BASE_URL=https://stale HARN_CONFIG="$kc" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1)
has "real run sets the key" "$OUT" "TOKEN=sk-test-1"
has "real run empties the api key" "$OUT" "APIKEY=[]"
has "real run clears inherited openai vars" "$OUT" "OAI=unset"
lacks "key never on argv" "$(printf '%s' "$OUT" | grep '^ARGS=')" "sk-test-1"

# Review Focus 2: a key_command argument with a space arrives as one argument.
stub printkey 'printf "%s" "$1"'
sp=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printkey", "two words"])')
OUT=$(HARN_CONFIG="$sp" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1)
has "key_command arg with a space" "$OUT" "TOKEN=two words"

fail=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["false"])')
OUT=$(HARN_CONFIG="$fail" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1); RC=$?
code "failing key_command" "$RC" 2
has "failing key_command names the provider" "$OUT" "key_command for 'openrouter' failed"

run claude gw
code "login provider with no stored key" "$RC" 2
has "points at harn login" "$OUT" "run: harn login openrouter"
```

Only if Task 1 recorded `PI_HERMES_BASE_URL=no`, append the `harness_names` test:

```bash
hn=$(cfgwith '.providers.openrouter.key_command = ["true"] | del(.providers.openrouter.login) | .providers.openrouter.harness_names = {"pi": "or"}')
OUT=$(HARN_CONFIG="$hn" "$HARN" pi gw m --show 2>&1)
has "harness_names renames the provider" "$OUT" "exec pi --provider or --model m"
```

Only if Task 1 recorded `LAUNCH_PI_HERMES=no`, append the slot object tests:

```bash
obj=$(cfgwith '.slots.gw = {"*": "openrouter", "pi": "ollama-cloud"} | .providers[] |= (if .kind == "endpoint" then (del(.login) | .key_command = ["true"]) else . end)')
OUT=$(HARN_CONFIG="$obj" "$HARN" pi gw m --show 2>&1)
has "slot object picks per harness" "$OUT" "# source: ollama-cloud"
OUT=$(HARN_CONFIG="$obj" "$HARN" claude gw --show 2>&1)
has "slot object falls back to *" "$OUT" "# source: openrouter"
```

- [ ] **Step 2: Run to see them fail**

Run: `/bin/bash tests/run.sh 2>&1 | grep -c '^FAIL'`
Expected: a non-zero count; the first endpoint failure is `claude gw --show` with the unknown-kind error.

- [ ] **Step 3: Implement the endpoint kind and credentials**

Add to `bin/harn` after `harn_kind_account`:

```bash
harn_kind_endpoint() {
  local wire bin base model key_env name wire_api tok
  local tp='{provider}' tm='{model}' tb='{base_url}' tk='{key_env}' tw='{wire_api}'
  wire=$(harn_harness_field wire)
  bin=$(harn_harness_field binary)
  base=$(harn_pfield ".${wire}_wire.base_url")
  [ -n "$base" ] || harn_die 2 "provider '$S_PROVIDER' has no ${wire}_wire, which $A_HARNESS needs" \
    "set providers.$S_PROVIDER.${wire}_wire.base_url in $HARN_CONFIG_PATH"
  model=${A_MODEL:-$(harn_pfield .default_model)}
  [ -n "$model" ] || harn_die 2 "no model given and provider '$S_PROVIDER' has no default" \
    "pass one: harn $A_HARNESS $A_SOURCE <model>" "or set providers.$S_PROVIDER.default_model"
  key_env=$(harn_key_env "$wire" "$S_PROVIDER")
  harn_credential
  case $wire in
    anthropic)
      harn_setenv ANTHROPIC_BASE_URL "$base"
      harn_setenv "$key_env" "$C_VALUE" "$C_SHOWN"
      if [ "$key_env" = ANTHROPIC_API_KEY ]; then
        harn_setenv ANTHROPIC_AUTH_TOKEN ''
      else
        harn_setenv ANTHROPIC_API_KEY ''
      fi
      X_ARGV=("$bin" --model "$model")
      ;;
    openai)
      harn_setenv "$key_env" "$C_VALUE" "$C_SHOWN"
      name=$S_PROVIDER
      wire_api=$(harn_pfield '.openai_wire.wire_api // "responses"')
      X_ARGV=("$bin")
      while IFS= read -r tok; do
        tok=${tok//"$tp"/$name}
        tok=${tok//"$tm"/$model}
        tok=${tok//"$tb"/$base}
        tok=${tok//"$tk"/$key_env}
        tok=${tok//"$tw"/$wire_api}
        X_ARGV+=("$tok")
      done < <(cfg --arg h "$A_HARNESS" '(.harness[$h].gw_argv // ["--provider", "{provider}", "--model", "{model}"])[]')
      ;;
    *) harn_die 2 "harness '$A_HARNESS' has unknown wire '$wire'" "wire is one of: anthropic, openai" ;;
  esac
  X_ARGV+=(${A_PASS[@]+"${A_PASS[@]}"})
}
```

Only if Task 1 recorded `PI_HERMES_BASE_URL=no`, resolve the name through `harness_names` instead:

```bash
      name=$(cfg --arg p "$S_PROVIDER" --arg h "$A_HARNESS" '.providers[$p].harness_names[$h] // $p')
```

Add a credentials section after the environment section:

```bash
# --- credentials

harn_credential() {
  local login has_cmd
  login=$(harn_pfield .login)
  has_cmd=$(harn_pfield '.key_command // empty | length')
  [ -z "$login" ] || [ -z "$has_cmd" ] || harn_die 2 "provider '$S_PROVIDER' sets both login and key_command" "keep one in $HARN_CONFIG_PATH"
  [ -n "$login" ] || [ -n "$has_cmd" ] || harn_die 2 "provider '$S_PROVIDER' has no credential" \
    "set providers.$S_PROVIDER.login or providers.$S_PROVIDER.key_command"
  if [ -n "$login" ]; then
    C_SHOWN="<redacted: login $login>"
  else
    C_SHOWN="<redacted: key_command $(harn_pfield '.key_command | join(" ")')>"
  fi
  C_VALUE=''
  [ "$A_SHOW" = 1 ] && return 0
  C_VALUE=$(harn_key_value "$S_PROVIDER") || exit 2
}

harn_key_value() {
  local p=$1 argv=() a out
  if [ -n "$(cfg --arg p "$p" '.providers[$p].key_command // empty | length')" ]; then
    while IFS= read -r a; do argv+=("$a"); done < <(cfg --arg p "$p" '.providers[$p].key_command[]')
    [ ${#argv[@]} -gt 0 ] || harn_die 2 "providers.$p.key_command is empty"
    out=$("${argv[@]}") || harn_die 2 "key_command for '$p' failed" "command: ${argv[*]}"
    [ -n "$out" ] || harn_die 2 "key_command for '$p' printed nothing" "command: ${argv[*]}"
    printf '%s' "$out"
    return 0
  fi
  harn_store_read "$p"
}

harn_store_read() { harn_die 2 "no stored key for '$1'" "run: harn login $1"; }
```

In `harn_main`, add the dispatch line under `account)`:

```bash
    endpoint) harn_kind_endpoint ;;
```

- [ ] **Step 4: Run to see them pass**

Run: `/bin/bash tests/run.sh | tail -n 1`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bin/harn tests/t_endpoint.sh
git commit -m "feat: add the endpoint kind with key_command credentials"
```

---

### Task 4: Launcher kind

Ends with `harn claude local qwen3-coder` exec'ing `ollama launch claude --model qwen3-coder` with passthrough, and a missing model leaving the launcher's picker.

**Files:**
- Modify: `bin/harn`
- Create: `tests/t_launcher.sh`

**Interfaces:**
- Consumes: Task 2 globals and run plan.
- Produces: `harn_kind_launcher`.

- [ ] **Step 1: Write the failing launcher tests**

`tests/t_launcher.sh`:

```bash
# Launcher kind.

run claude local qwen3-coder --show
code "claude local --show" "$RC" 0
has "labels local" "$OUT" "# source: ollama (local)"
has "launcher argv" "$OUT" "exec ollama launch claude --model qwen3-coder"

run codex local qwen3-coder --show -- -p "hi there"
has "launcher passthrough after --" "$OUT" "exec ollama launch codex --model qwen3-coder -- -p hi\\ there"

run pi local --show
code "launcher without a model" "$RC" 0
has "no --model leaves the picker" "$OUT" "exec ollama launch pi"
lacks "no --model flag" "$OUT" "--model"

stub ollama 'printf "OAI=%s ARGS=%s\n" "${OPENAI_API_KEY-unset}" "$*"'
OUT=$(OPENAI_API_KEY=stale PATH="$STUBS:$PATH" "$HARN" codex local m 2>&1)
has "launcher clears inherited keys" "$OUT" "OAI=unset"
has "launcher real argv" "$OUT" "ARGS=launch codex --model m"

str=$(cfgwith '.providers.ollama.launcher = "ollama launch"')
OUT=$(HARN_CONFIG="$str" "$HARN" claude local m --show 2>&1); RC=$?
code "string launcher is a config error" "$RC" 2
has "names the launcher field" "$OUT" "providers.ollama.launcher"
```

If Task 1 recorded `LAUNCH_PI_HERMES=no`, `slots.local` sends pi to the `ollama-api` endpoint: change the `pi local --show` case to expect `# source: ollama-api (local)` and `--model qwen3-coder` from that provider's default, and use `claude` for the no-model picker case.

- [ ] **Step 2: Run to see them fail**

Run: `/bin/bash tests/run.sh | grep '^FAIL' | head -n 3`
Expected: `FAIL: claude local --show` and the tests after it.

- [ ] **Step 3: Implement**

Add after `harn_kind_endpoint`:

```bash
harn_kind_launcher() {
  local a
  [ "$(harn_pfield '.launcher | type')" = array ] || harn_die 2 "providers.$S_PROVIDER.launcher must be an argv array" \
    "for example: [\"ollama\", \"launch\"]"
  X_ARGV=()
  while IFS= read -r a; do X_ARGV+=("$a"); done < <(harn_pfield '.launcher[]')
  [ ${#X_ARGV[@]} -gt 0 ] || harn_die 2 "providers.$S_PROVIDER.launcher is empty"
  X_ARGV+=("$A_HARNESS")
  A_MODEL=${A_MODEL:-$(harn_pfield .default_model)}
  [ -z "$A_MODEL" ] || X_ARGV+=(--model "$A_MODEL")
  [ ${#A_PASS[@]} -eq 0 ] || X_ARGV+=(-- "${A_PASS[@]}")
}
```

In `harn_main` add under `endpoint)`:

```bash
    launcher) harn_kind_launcher ;;
```

- [ ] **Step 4: Run to see them pass**

Run: `/bin/bash tests/run.sh | tail -n 1`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bin/harn tests/t_launcher.sh
git commit -m "feat: add the launcher kind for local models"
```

---

### Task 5: Key file, paste login and `harn key`

Ends with `harn login ollama-cloud` storing a pasted key, `harn claude ollama-cloud` using it and `harn key` printing it.

**Files:**
- Modify: `bin/harn`
- Create: `tests/t_store.sh`

**Interfaces:**
- Consumes: `harn_key_value`, `harn_load_config`, `cfg`.
- Produces:
  - `harn_store_write PROVIDER` (key on stdin; prints the file written), `harn_store_read PROVIDER` (replaces Task 3's).
  - `harn_cmd_login PROVIDER [ARGS...]`, `harn_login_paste PROVIDER`, `harn_cmd_key PROVIDER`.

- [ ] **Step 1: Write the failing store tests**

`tests/t_store.sh`:

```bash
# File key store, paste login, harn key.

printf 'sk-oc-pasted \n' | "$HARN" login ollama-cloud >/dev/null 2>&1
code "paste login exits 0" "$?" 0
f="$XDG_STATE_HOME/harn/keys/ollama-cloud"
[ -f "$f" ] && ok "key file written" || bad "key file written"
perm=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")
code "key file is 0600" "$perm" 600
# Review Focus 4: byte-exact round trip: 13 bytes, the last one the trailing space, no newline added.
code "stored key is 13 bytes" "$(wc -c < "$f" | tr -d ' ')" 13
[ "$(tail -c 1 "$f")" = " " ] && ok "trailing space kept, no newline" || bad "trailing space kept, no newline" "$(od -c "$f")"

run key ollama-cloud
code "harn key exits 0" "$RC" 0
has "harn key prints the key" "$OUT" "sk-oc-pasted"

stub claude 'printf "TOKEN=[%s]\n" "$ANTHROPIC_AUTH_TOKEN"'
OUT=$(PATH="$STUBS:$PATH" "$HARN" claude ollama-cloud 2>&1)
has "endpoint uses the stored key" "$OUT" "TOKEN=[sk-oc-pasted ]"

run claude ollama-cloud --show
has "paste redaction" "$OUT" "<redacted: login paste>"

kc=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printf", "%s", "from-cmd"])')
OUT=$(HARN_CONFIG="$kc" "$HARN" key openrouter 2>&1)
has "harn key runs key_command" "$OUT" "from-cmd"

printf 'sk-oc-second' | "$HARN" login ollama-cloud >/dev/null 2>&1
run key ollama-cloud
has "a second login overwrites the key" "$OUT" "sk-oc-second"
rm -f "$f"
run key ollama-cloud
code "key after the file is deleted" "$RC" 2
has "missing key points at login" "$OUT" "run: harn login ollama-cloud"

printf '\n' | "$HARN" login ollama-cloud >/dev/null 2>&1
code "empty paste is refused" "$?" 2

run login nope
code "login for an unknown provider" "$RC" 2
```

- [ ] **Step 2: Run to see them fail**

Run: `/bin/bash tests/run.sh | grep '^FAIL' | head -n 3`
Expected: `FAIL: key file written` (the `login` subcommand does not exist yet).

- [ ] **Step 3: Implement the store and subcommands**

Add a key store section after the credentials section:

```bash
# --- key store

harn_store_file() { printf '%s/harn/keys/%s' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"; }

harn_store_write() {
  local f key
  f=$(harn_store_file "$1")
  key=$(cat; printf x)
  key=${key%x}
  (umask 077 && mkdir -p "$(dirname "$f")" && printf '%s' "$key" > "$f") \
    || harn_die 3 "cannot write $f"
  printf '%s\n' "$f"
}

harn_store_read() {
  local f
  f=$(harn_store_file "$1")
  [ -r "$f" ] || harn_die 2 "no stored key for '$1'" "run: harn login $1"
  cat "$f"
}
```

Note `harn_store_read` prints without a trailing newline, and `C_VALUE=$(...)` in `harn_credential` keeps a trailing space because only newlines are stripped.

Replace Task 3's one-line `harn_store_read` with the function above (delete the stub).

Add a logins and subcommands section before `# --- main`:

```bash
# --- logins

harn_provider_exists() {
  [ -n "$(cfg --arg p "$1" '.providers[$p].kind // empty')" ] || harn_die 2 "unknown provider '$1'" \
    "known: $(cfg '.providers // {} | keys | join(", ")')"
}

harn_cmd_login() {
  local p=${1:-} login
  [ -n "$p" ] || harn_die 2 "usage: harn login <provider> [--no-open]"
  shift
  harn_provider_exists "$p"
  login=$(cfg --arg p "$p" '.providers[$p].login // empty')
  case $login in
    paste) harn_login_paste "$p" ;;
    openrouter-pkce) harn_login_pkce "$p" "$@" ;;
    '') harn_die 2 "provider '$p' has no login" "it uses key_command; nothing to store" ;;
    *) harn_die 2 "provider '$p' has unknown login '$login'" "login is one of: openrouter-pkce, paste" ;;
  esac
}

harn_login_paste() {
  local p=$1 key b
  printf 'Paste the key for %s (input hidden): ' "$p" >&2
  IFS= read -rs key || true
  printf '\n' >&2
  [ -n "$key" ] || harn_die 2 "no key entered"
  b=$(printf '%s' "$key" | harn_store_write "$p") || exit $?
  printf 'harn: stored the key for %s in %s\n' "$p" "$b" >&2
}

harn_cmd_key() {
  [ -n "${1:-}" ] || harn_die 2 "usage: harn key <provider>"
  harn_provider_exists "$1"
  harn_key_value "$1"
  printf '\n'
}


```

In `harn_main`, after the `--version` case and before `harn_load_config`, route the subcommands:

```bash
  case ${1:-} in
    login) shift; harn_load_config; harn_cmd_login "$@"; exit $? ;;
    key) shift; harn_load_config; harn_cmd_key "$@"; exit $? ;;
  esac
```

Stub for Task 6, so the dispatch compiles: add `harn_login_pkce() { harn_die 3 "openrouter-pkce is not implemented yet"; }` in the logins section. Task 6 replaces it.

- [ ] **Step 4: Run to see them pass**

Run: `/bin/bash tests/run.sh | tail -n 1`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bin/harn tests/t_store.sh
git commit -m "feat: add the key file, paste login and harn key"
```

---

### Task 6: OpenRouter PKCE login

Ends with `harn login openrouter` obtaining a key through OpenRouter's headless flow and `harn claude gw` using it, proven against a stub `curl` and then once for real.

**Files:**
- Modify: `bin/harn`
- Create: `tests/t_pkce.sh`

**Interfaces:**
- Consumes: `harn_store_write`, `harn_require`, `harn_die`.
- Produces: `harn_b64url` (stdin to stdout), `harn_pkce_verifier`, `harn_pkce_challenge VERIFIER`, `harn_login_pkce PROVIDER [--no-open]`.

- [ ] **Step 1: Write the failing PKCE tests**

`tests/t_pkce.sh`:

```bash
# OpenRouter PKCE login against a stub curl.

OUT=$(HARN_PKCE_SELFTEST=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk "$HARN" --pkce-selftest 2>&1)
has "RFC 7636 appendix B challenge" "$OUT" "challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
v=$(printf '%s\n' "$OUT" | sed -n 's/^verifier=//p')
printf '%s' "$v" | grep -Eq '^[A-Za-z0-9_-]{64}$' && ok "generated verifier shape" || bad "generated verifier shape" "$v"

rec=$(mktemp -d)
stub curl "printf '%s\n' \"\$@\" > '$rec/argv'; cat > '$rec/stdin'; printf '{\"key\":\"sk-or-from-pkce\"}'"
stub open "echo opened >> '$rec/opened'; exit 1"
stub xdg-open "echo opened >> '$rec/opened'; exit 1"
OUT=$(printf 'the-code-123\n' | PATH="$STUBS:$PATH" "$HARN" login openrouter --no-open 2>&1); RC=$?
code "pkce login exits 0" "$RC" 0
has "prints the auth URL" "$OUT" "https://openrouter.ai/auth?code_challenge="
has "URL uses S256" "$OUT" "code_challenge_method=S256"
has "URL labels the key" "$OUT" "key_label=harn-"
has "posts to the keys endpoint" "$(cat "$rec/argv")" "https://openrouter.ai/api/v1/auth/keys"
has "uses POST" "$(cat "$rec/argv")" "POST"
has "body carries the code" "$(cat "$rec/stdin")" '"code":"the-code-123"'
has "body carries S256" "$(cat "$rec/stdin")" '"code_challenge_method":"S256"'
body_v=$(jq -r .code_verifier "$rec/stdin")
[ "${#body_v}" = 64 ] && ok "body carries the verifier" || bad "body carries the verifier" "$body_v"
lacks "code not on argv" "$(cat "$rec/argv")" "the-code-123"
lacks "verifier not on argv" "$(cat "$rec/argv")" "$body_v"
[ -e "$rec/opened" ] && bad "--no-open opens nothing" || ok "--no-open opens nothing"
run key openrouter
has "stored the returned key" "$OUT" "sk-or-from-pkce"

stub curl "cat > /dev/null; printf '{\"error\":{\"message\":\"invalid code\"}}'"
OUT=$(printf 'bad\n' | PATH="$STUBS:$PATH" "$HARN" login openrouter --no-open 2>&1); RC=$?
code "response without key" "$RC" 2
has "shows the API error" "$OUT" "invalid code"
rm -f "$XDG_STATE_HOME/harn/keys/openrouter"
```

`HARN_PKCE_SELFTEST` and `--pkce-selftest` are a test seam: with the variable set, `harn --pkce-selftest` prints the challenge of that verifier plus one freshly generated verifier, and touches nothing else.

- [ ] **Step 2: Run to see them fail**

Run: `/bin/bash tests/run.sh | grep '^FAIL' | head -n 3`
Expected: `FAIL: RFC 7636 appendix B challenge`.

- [ ] **Step 3: Implement**

Replace the Task 5 stub `harn_login_pkce` with:

```bash
harn_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
harn_pkce_verifier() { openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n'; }
harn_pkce_challenge() { printf '%s' "$1" | openssl dgst -sha256 -binary | harn_b64url; }

harn_login_pkce() {
  local p=$1 open=1 verifier challenge url code body resp key b
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      --no-open) open=0; shift ;;
      *) harn_die 2 "unknown flag: $1" "usage: harn login $p [--no-open]" ;;
    esac
  done
  harn_require curl openssl
  verifier=$(harn_pkce_verifier)
  challenge=$(harn_pkce_challenge "$verifier")
  url="https://openrouter.ai/auth?code_challenge=$challenge&code_challenge_method=S256&key_label=harn-$(hostname -s)"
  printf 'Open this URL, approve, then paste the code it shows:\n  %s\n' "$url" >&2
  if [ "$open" = 1 ]; then
    if command -v open >/dev/null 2>&1; then
      open "$url" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$url" >/dev/null 2>&1 || true
    fi
  fi
  printf 'Code: ' >&2
  IFS= read -r code || true
  [ -n "$code" ] || harn_die 2 "no code entered"
  body=$(jq -cn --arg c "$code" --arg v "$verifier" '{code: $c, code_verifier: $v, code_challenge_method: "S256"}')
  resp=$(printf '%s' "$body" | curl -sS --fail-with-body -X POST https://openrouter.ai/api/v1/auth/keys \
    -H 'Content-Type: application/json' --data @-) || true
  key=$(printf '%s' "$resp" | jq -r '.key // empty' 2>/dev/null)
  [ -n "$key" ] || harn_die 2 "OpenRouter returned no key" \
    "$(printf '%s' "$resp" | jq -r '.error.message // .error // "no error message"' 2>/dev/null || printf '%s' "$resp")"
  b=$(printf '%s' "$key" | harn_store_write "$p") || exit $?
  printf 'harn: stored the key for %s in %s\n' "$p" "$b" >&2
}
```

In `harn_main`, next to `--version`, add the self-test seam:

```bash
    --pkce-selftest)
      [ -n "${HARN_PKCE_SELFTEST:-}" ] || harn_die 2 "--pkce-selftest needs HARN_PKCE_SELFTEST"
      harn_require openssl
      printf 'challenge=%s\nverifier=%s\n' "$(harn_pkce_challenge "$HARN_PKCE_SELFTEST")" "$(harn_pkce_verifier)"
      exit 0
      ;;
```

- [ ] **Step 4: Run to see them pass**

Run: `/bin/bash tests/run.sh | tail -n 1`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Real login, done by the R&D lead**

Stop and ask the R&D lead to run, in their own terminal:

```bash
bin/harn login openrouter
bin/harn claude gw --show
```
Then confirm in the OpenRouter dashboard that a key labelled `harn-<hostname>` exists, and note which workspace it landed in. Afterwards delete `~/.local/state/harn/keys/openrouter` and revoke the test key on `https://openrouter.ai/settings/keys`.

- [ ] **Step 6: Commit**

```bash
git add bin/harn tests/t_pkce.sh
git commit -m "feat: add OpenRouter PKCE login"
```

---

### Task 7: Config subcommands, help and the old-install stub

Ends with `harn config`, `harn config init [--force]`, `harn config edit` and `harn --help` working, including through a symlink, and an old `.zshrc` getting a one-line instruction instead of a broken function.

**Files:**
- Modify: `bin/harn`, `lib/harn.zsh` (replace with stub)
- Create: `tests/t_config.sh`

**Interfaces:**
- Consumes: `HARN_TEMPLATE`, `HARN_CONFIG_PATH`, `harn_load_config`.
- Produces: `harn_cmd_config [init [--force] | edit]`, `harn_help`.

- [ ] **Step 1: Write the failing tests**

`tests/t_config.sh`:

```bash
# Config subcommands, help, symlinked install, old-install stub.

run config
code "config prints" "$RC" 0
has "config prints providers" "$OUT" '"providers"'

d=$(mktemp -d)
OUT=$(HARN_CONFIG="$d/config.json" "$HARN" config init 2>&1); RC=$?
code "init writes" "$RC" 0
jq -e '.slots.gw == "openrouter"' "$d/config.json" >/dev/null && ok "init content" || bad "init content"
OUT=$(HARN_CONFIG="$d/config.json" "$HARN" config init 2>&1); RC=$?
code "init refuses to overwrite" "$RC" 2
has "init names --force" "$OUT" "--force"
OUT=$(HARN_CONFIG="$d/config.json" "$HARN" config init --force 2>&1); RC=$?
code "init --force overwrites" "$RC" 0

# Review Focus 5: a symlinked binary still finds the template.
ln -s "$HARN" "$d/harn"
OUT=$(HARN_CONFIG="$d/new.json" "$d/harn" config init 2>&1); RC=$?
code "symlinked init" "$RC" 0
[ -f "$d/new.json" ] && ok "symlinked init wrote the template" || bad "symlinked init wrote the template"

run --help
code "help exits 0" "$RC" 0
has "help shows usage" "$OUT" "usage: harn <harness>"
has "help lists login" "$OUT" "harn login <provider>"

if command -v zsh >/dev/null 2>&1; then
  OUT=$(zsh -c "source '$ROOT/lib/harn.zsh'" 2>&1)
  has "stub tells old installs what to change" "$OUT" "put bin/harn on your PATH"
fi
```

- [ ] **Step 2: Run to see them fail**

Run: `/bin/bash tests/run.sh | grep '^FAIL' | head -n 3`
Expected: `FAIL: config prints`.

- [ ] **Step 3: Implement**

Add before `# --- main`:

```bash
# --- subcommands

harn_help() {
  cat <<'EOF'
usage: harn <harness> [<source>] [<model>] [--show] [-- <args>...]

Sources:
  (none) or account     the harness's own subscription login
  gw, local             whatever that slot points at in the config
  <provider>            a named provider, for a one-off

Commands:
  harn login <provider> [--no-open]
  harn key <provider>          print the provider's key, for reuse by another command
  harn config                  print the resolved config
  harn config init [--force]   write the template config
  harn config edit             open the config in $EDITOR
  harn --version

Examples:
  harn claude
  harn claude gw
  harn codex gw openai/gpt-6-sol
  harn claude local qwen3-coder -- -p "hello"
  harn claude ollama-cloud --show
EOF
}

harn_cmd_config() {
  case ${1:-} in
    '') harn_load_config; jq . <<<"$HARN_CFG" ;;
    edit) exec "${EDITOR:-vi}" "$HARN_CONFIG_PATH" ;;
    init)
      if [ -e "$HARN_CONFIG_PATH" ] && [ "${2:-}" != --force ]; then
        harn_die 2 "$HARN_CONFIG_PATH already exists" "pass --force to overwrite it"
      fi
      mkdir -p "$(dirname "$HARN_CONFIG_PATH")" && cp "$HARN_TEMPLATE" "$HARN_CONFIG_PATH" \
        || harn_die 2 "cannot write $HARN_CONFIG_PATH"
      printf 'wrote %s\n' "$HARN_CONFIG_PATH"
      ;;
    *) harn_die 2 "unknown config subcommand '$1'" "use: harn config [init [--force] | edit]" ;;
  esac
}
```

In `harn_main`, extend the first `case` so it reads:

```bash
  case ${1:-} in
    --version) printf 'harn %s\n' "$HARN_VERSION"; exit 0 ;;
    --help|-h|help) harn_help; exit 0 ;;
    config) shift; harn_cmd_config "$@"; exit $? ;;
  esac
```

(keeping the `--pkce-selftest` branch from Task 6 in the same `case`).

Replace `lib/harn.zsh` entirely with:

```zsh
# harn is now an executable (bin/harn). This file remains only so an old shell startup line keeps working.
print -u2 "harn: remove the 'source .../lib/harn.zsh' line from your shell startup file and put bin/harn on your PATH (see README)"
```

- [ ] **Step 4: Run to see them pass**

Run: `/bin/bash tests/run.sh | tail -n 1`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Migrate the R&D lead's own install**

Stop and ask before touching `~/.zshrc` or `~/.config/harn/config.json`. With a yes: back up the config to `~/.config/harn/config.0x.json`, write the 0.1 config by the spec's Migration mapping (the `openrouter` provider keeps its `key_command` built from the old `key_ref`), replace the `source` line with a symlink `~/.local/bin/harn -> ~/Developer/personal/harn/bin/harn`, then run `harn claude gw --show` and `harn codex --show` and compare with the legacy output.

- [ ] **Step 6: Commit**

```bash
git add bin/harn lib/harn.zsh tests/t_config.sh
git commit -m "feat: add config subcommands and help; reduce lib/harn.zsh to a migration stub"
```

---

### Task 8: Repository documents

Ends with a repository a stranger can install, use, contribute to and report a vulnerability in, matching the spec's file list.

**Files:**
- Modify: `README.md`, `AGENTS.md`
- Create: `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/bug.yml`, `.github/ISSUE_TEMPLATE/feature.yml`
- Keep: `CLAUDE.md` symlink to `AGENTS.md` (already present; verify with `readlink CLAUDE.md`)

**Interfaces:**
- Consumes: the final command set from Tasks 2 to 7.
- Produces: documentation only.

- [ ] **Step 1: Write a failing docs check**

Append to `tests/t_config.sh`:

```bash
# Docs name every command the help text names, and nothing that no longer exists.
for w in "harn login" "harn key" "harn config init" "--show" "brew tap dean-harel/harn https://github.com/dean-harel/harn" "brew install dean-harel/harn/harn"; do
  grep -qF -- "$w" "$ROOT/README.md" && ok "README mentions $w" || bad "README mentions $w"
done
for w in "lib/harn.zsh is sourced" "key_ref" "active.gateway" " -l "; do
  grep -qF -- "$w" "$ROOT/README.md" && bad "README drops $w" || ok "README drops $w"
done
for f in CONTRIBUTING.md SECURITY.md .github/ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/feature.yml; do
  [ -f "$ROOT/$f" ] && ok "$f exists" || bad "$f exists"
done
```

Run: `/bin/bash tests/run.sh | grep '^FAIL' | head -n 5`
Expected: FAIL lines for the README and the missing files.

- [ ] **Step 2: Rewrite README.md**

Sections, in order, with this content:

1. `# harn` and one sentence: "One command for any AI coding harness (Claude Code, Codex, Pi, Hermes Agent), against your subscription, a gateway API or a local model."
2. **Where it fits:** "For OpenRouter alone, OpenRouter's own Ori Harness is the vendor-supported launcher. harn is for switching between your subscription, one or more gateways and local models with one command, and it keeps your keys out of dotfiles."
3. **Install:** `brew tap dean-harel/harn https://github.com/dean-harel/harn && brew install dean-harel/harn/harn`, or `git clone --branch vX.Y.Z git@github.com:dean-harel/harn.git ~/src/harn && ln -s ~/src/harn/bin/harn ~/.local/bin/harn`. Requirements: `jq`, `curl`, `openssl`.
4. **Use:** the Interface block from the spec, verbatim, plus three worked examples: first run (`harn config init`, `harn login openrouter`, `harn claude gw`), swapping the gw slot to `ollama-cloud`, and a local model (`ollama pull qwen3-coder`, `harn claude local qwen3-coder`).
5. **Config:** the template, then one paragraph each on slots, providers and kinds, and credentials (`login`, `key_command` with the `op read` and `printenv` examples, and a native OpenRouter entry for users who prefer a key they manage). Add a paragraph on `harness_names` or the slot object form only if Task 1 built them.
6. **Where keys live:** one 0600 file per provider under `${XDG_STATE_HOME:-~/.local/state}/harn/keys/`; `harn key` prints one. Removing a key means deleting its file and revoking it on the provider's keys page (`https://openrouter.ai/settings/keys` for OpenRouter); deleting the file alone leaves the key valid.
7. **Limits:** pi and hermes swap only among providers their registry knows (per Task 1's answer); local models need Ollama installed and the model pulled.
8. **Upgrading from the zsh function:** the spec's Migration bullets.
9. **Develop:** `/bin/bash tests/run.sh`; `--show` for any command.

- [ ] **Step 3: Rewrite AGENTS.md**

```markdown
# harn

A single executable, `bin/harn`, that runs an AI coding harness against a subscription, a
gateway API or a local model. bash 3.2 plus `jq`, `curl` and `openssl`.

## Run and test

    /bin/bash tests/run.sh      # the whole suite; must pass on macOS /bin/bash and on Linux
    bin/harn <harness> ... --show

The suite runs bin/harn as a child process against a temporary HOME, never launches a real
harness and never reaches the network. Keys land in the temporary HOME's state directory, and
HARN_PKCE_SELFTEST with --pkce-selftest exposes the PKCE math.

## Invariants

- **bash 3.2.** No mapfile, no associative arrays, empty arrays as ${a[@]+"${a[@]}"} under set -u.
  CI runs the suite under macOS /bin/bash to catch a violation.
- **A key never reaches argv or output.** It travels through the harness's environment only;
  --show prints a redaction and never resolves a credential. harn key is the one command that
  prints a key. A test pins each of these.
- **Every run clears before it sets.** harn_clean_vars lists everything a run unsets; a new
  provider variable belongs there.
- **Command-shaped config is an argv array.**

## Layout

bin/harn is sectioned in order: messages, paths, config, parsing, sources, kinds, environment,
credentials, key store, logins, run, subcommands, main. lib/config.template.json is the shipped
config. lib/harn.zsh is a stub for startup files from the zsh-function era. Formula/harn.rb makes
the repository its own Homebrew tap. Specs and plans are in .agents/.

## Conventions

Conventional Commits; release-please cuts releases from main. No attribution lines anywhere.
```

- [ ] **Step 4: Write CONTRIBUTING.md, SECURITY.md and the issue templates**

`CONTRIBUTING.md`:

```markdown
# Contributing

harn's core is small on purpose: resolve a source, build an environment and an argv, exec. A new
harness or provider is a config entry, not a code change. Changes that grow the core need an
issue first.

Before a pull request: `/bin/bash tests/run.sh` passes, `shellcheck --shell=bash bin/harn
tests/*.sh` is clean, and the title is a Conventional Commit. Do not edit CHANGELOG.md;
release-please writes it. You must understand every line you submit, including any an agent
wrote.
```

`SECURITY.md`:

```markdown
# Security

harn runs as you, reads your config, and passes keys to the harness it launches. Your own
account, files, environment, shell startup files, config and key store are inside that trust
boundary: a report that needs prior write access to them is out of scope unless harn itself
grants that access.

In scope: a key reaching argv, output, logs or any file outside the key store; --show resolving
a credential; a run inheriting a previous provider's variables; the PKCE flow leaking its code
or verifier.

Report privately through GitHub Security Advisories on this repository. Include the version
(`harn --version`), the platform, and steps to reproduce.
```

`.github/ISSUE_TEMPLATE/bug.yml`:

```yaml
name: Bug
description: Something harn does wrong
body:
  - type: input
    id: version
    attributes: { label: harn --version }
    validations: { required: true }
  - type: textarea
    id: show
    attributes:
      label: Output of the command with --show
      description: --show never prints a key, so it is safe to paste.
    validations: { required: true }
  - type: textarea
    id: expected
    attributes: { label: What you expected instead }
    validations: { required: true }
```

`.github/ISSUE_TEMPLATE/feature.yml`:

```yaml
name: Feature
description: A harness, provider or behaviour harn should support
body:
  - type: textarea
    id: need
    attributes: { label: What you are trying to do, and why config alone cannot do it }
    validations: { required: true }
```

- [ ] **Step 5: Run to see the docs check pass**

Run: `/bin/bash tests/run.sh | tail -n 1`
Expected: `N passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add README.md AGENTS.md CONTRIBUTING.md SECURITY.md .github/ISSUE_TEMPLATE tests/t_config.sh
git commit -m "docs: rewrite the README and agent guide; add contributing and security policies"
```

---

### Task 9: Release pipeline and Homebrew formula

Ends with a merged release PR producing tag `v0.1.0`, and `brew install dean-harel/harn/harn` installing that tag from the repository's own tap.

**Files:**
- Create: `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release.yml`, `Formula/harn.rb`

**Interfaces:**
- Consumes: the `HARN_VERSION` line in `bin/harn` (Task 2).
- Produces: the formula's `tag:` line, which release-please rewrites in each release PR alongside `HARN_VERSION`.

- [ ] **Step 1: Write a failing release-config check**

Append to `tests/t_config.sh`:

```bash
jq -e '.packages["."] | .["release-type"] == "simple" and .["bump-minor-pre-major"] == true
  and (.["extra-files"] | index("bin/harn") and index("Formula/harn.rb"))' \
  "$ROOT/release-please-config.json" >/dev/null 2>&1 && ok "release-please config" || bad "release-please config"
grep -q 'x-release-please-version' "$ROOT/bin/harn" && ok "version marker in bin/harn" || bad "version marker in bin/harn"
grep -q 'tag: "v[0-9.]*" # x-release-please-version' "$ROOT/Formula/harn.rb" 2>/dev/null \
  && ok "version marker in the formula" || bad "version marker in the formula"
```

Run: `/bin/bash tests/run.sh | grep '^FAIL'`
Expected: `FAIL: release-please config` and `FAIL: version marker in the formula`.

- [ ] **Step 2: Add the release-please files**

`release-please-config.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "simple",
      "package-name": "harn",
      "include-component-in-tag": false,
      "bump-minor-pre-major": true,
      "extra-files": ["bin/harn", "Formula/harn.rb"]
    }
  }
}
```

`.release-please-manifest.json`:

```json
{ ".": "0.0.0" }
```

From `0.0.0`, the branch's `feat!` commit gives `0.1.0`, since `bump-minor-pre-major` turns a breaking change on 0.x into a minor bump.

- [ ] **Step 3: Add the formula**

`Formula/harn.rb`:

```ruby
class Harn < Formula
  desc "One command for any AI coding harness: subscription, gateway or local model"
  homepage "https://github.com/dean-harel/harn"
  url "https://github.com/dean-harel/harn.git",
      tag: "v0.1.0" # x-release-please-version
  license "MIT"
  head "https://github.com/dean-harel/harn.git", branch: "main"

  depends_on "jq"
  uses_from_macos "curl"

  def install
    libexec.install "bin", "lib"
    bin.install_symlink libexec/"bin/harn"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/harn --version")
    assert_match "usage: harn", shell_output("#{bin}/harn --help")
  end
end
```

Installing from the git tag means a release uploads nothing and needs no token or second repository. Until the `v0.1.0` tag exists, `brew install` fails on the missing tag, which is the intended guard.

Run: `ruby -c Formula/harn.rb && /bin/bash tests/run.sh | tail -n 1`
Expected: `Syntax OK`, then `N passed, 0 failed`.

- [ ] **Step 4: Add the release workflow**

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

The release job alone holds `contents: write` and `pull-requests: write`.

- [ ] **Step 5: Commit, then stop for the outward steps**

```bash
/bin/bash tests/run.sh | tail -n 1
git add release-please-config.json .release-please-manifest.json .github/workflows/release.yml Formula/harn.rb tests/t_config.sh
git commit -m "ci: release with release-please; make the repository its own Homebrew tap"
```
Expected: `N passed, 0 failed`, then the commit.

Stop and ask the R&D lead, one act at a time:
1. Push `feat/providers` and open the PR; CI must pass on both platforms and `shellcheck`.
2. Merge the PR, then check that the release PR release-please opens says `0.1.0` and rewrites both marked lines, and merge it.

- [ ] **Step 6: Verify the release**

```bash
gh release view v0.1.0 -R dean-harel/harn --json tagName --jq .tagName
brew tap dean-harel/harn https://github.com/dean-harel/harn && brew install dean-harel/harn/harn && harn --version && brew test dean-harel/harn/harn
```
Expected: `v0.1.0`; then `harn 0.1.0`; then the formula test passes.
