# Codex harness support

Date: 2026-05-17
Status: approved (design phase)

## Goal

Add the `codex` harness (OpenAI's Codex CLI) to harn with full support for all three modes: `account`, `gw`, and `local`. Keep harn's "new harnesses are a config edit, not a code change" property intact.

## Background

Today harn supports two harnesses:

- `claude`, wire `anthropic`, modes account/gw/local.
- `pi`, wire `openai`, modes gw/local.

The gateway path is wire-specific:

- Anthropic wire injects `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`, then execs the binary.
- OpenAI wire exports `<UPPER(gw)>_API_KEY` (or `gateway.<name>.key_env`) and execs `<binary> --provider <gw> --model <model>`.

Codex is OpenAI-wire semantically, but the CLI does not take `--provider <name>`. Codex routes alternate endpoints through `~/.codex/config.toml` `[model_providers.<name>]` entries, selected per-invocation with `-c model_provider=<name> --model <model>`. The API key is read from the env var named by `env_key` in that toml block.

So a config-only addition of `codex` is not enough: the openai gw path's argv shape is wired to pi.

## Approach

Generalize the openai gw path with a per-harness `gw_argv` template. Each openai-wire harness declares how to spell "use gateway X with model Y" in its own argv. Pi keeps its current shape; codex gets its own. Future openai-wire harnesses are then config-only additions, as advertised.

Account-mode env hygiene is derived from `wire` (no new field): anthropic clears the Anthropic trio, openai clears `OPENAI_API_KEY` and `OPENAI_BASE_URL`. This guarantees ChatGPT subscription auth in codex account mode, mirroring how claude account mode guarantees the Anthropic subscription path.

## Schema changes

One new optional field on `harness.<name>`:

```json
"gw_argv": ["-c", "model_provider={gw}", "--model", "{model}"]
```

- Type: array of strings.
- Applies only to openai-wire harnesses. Ignored for anthropic-wire (which has its own env-injection contract).
- Placeholders: `{gw}` (active gateway name), `{model}` (model id from argv). Substitution is whole-token literal replacement.
- Default when absent (openai wire only): `["--provider", "{gw}", "--model", "{model}"]`. This preserves pi's current invocation without forcing a config migration.
- Passthrough args (`-- ...`) are appended after the templated argv, unchanged from today.

No other schema changes.

## Config template

`lib/config.template.json` gains a `codex` harness and an explicit `gw_argv` on `pi` (explicit even when it matches the default, to make the contract discoverable in the template):

```json
"harness": {
  "claude": { "wire": "anthropic", "binary": "claude", "supports": ["account","gw","local"], "default": "account" },
  "codex":  { "wire": "openai",    "binary": "codex",  "supports": ["account","gw","local"], "default": "account",
              "gw_argv": ["-c", "model_provider={gw}", "--model", "{model}"] },
  "pi":     { "wire": "openai",    "binary": "pi",     "supports": ["gw","local"],            "default": null,
              "gw_argv": ["--provider", "{gw}", "--model", "{model}"] }
}
```

## Code changes in `lib/harn.zsh`

Three targeted edits, no new files.

### 1. `_harn_do_account` becomes wire-aware

Today it unconditionally unsets the Anthropic trio. Change to dispatch on the harness's wire:

- `anthropic`: unset `ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY` (current behavior).
- `openai`: unset `OPENAI_API_KEY OPENAI_BASE_URL`.

The `--show` branch prints the matching `unset` line.

### 2. `_harn_do_gw_openai` reads `gw_argv`

Replace the hardcoded `exec "$binary" --provider "$gw_name" --model "$_A_MODEL" "${_A_PASSTHROUGH[@]}"` with:

1. Read `harness.<h>.gw_argv` as a JSON array; if absent, use the default array `["--provider", "{gw}", "--model", "{model}"]`.
2. Substitute `{gw}` -> `$gw_name` and `{model}` -> `$_A_MODEL` in each element.
3. Build the final argv as `(${binary} ${substituted_argv[@]} ${_A_PASSTHROUGH[@]})`.
4. Exec (or print for `--show`).

The env-export half of the function (`export "$key_env=$key"`) is unchanged.

### 3. New helper `_harn_harness_gw_argv`

Reads the JSON array via `jq -r '... | .[]'` and pipes into a zsh array. Mirrors the style of the existing `_harn_harness_*` helpers. Returns the default array if the field is absent.

### Unchanged

Argument parsing, mode resolution, anthropic gw path, local mode, key resolution, subcommands, error helpers.

## Tests

`tests/dry-run.sh` gains:

- Codex account: assert `--show` output contains `unset OPENAI_API_KEY OPENAI_BASE_URL` and `exec codex` (plus any passthrough).
- Codex gw: assert `--show` output contains the templated argv `exec codex -c model_provider=<gw> --model <m>` and the gateway key env export.
- Codex local: assert `--show` output exec line matches `<launcher> codex --model <m>`.
- Pi gw regression: assert `--show` still produces `exec pi --provider <gw> --model <m>`, confirming the template default and the explicit-template path agree.
- Claude account regression: unchanged behavior (still unsets the Anthropic trio).

## Documentation

`README.md`:

- Extend the schema block to include `gw_argv` on `harness.<name>`, with a one-line description.
- Add a paragraph to "Gateway mode" explaining that openai-wire argv is templated per harness, with `{gw}` and `{model}` placeholders, defaulting to pi's shape.
- Add a codex example to the example list at the top.

## Out of scope

- Anthropic-wire argv templating. Anthropic gw is purely env-injected; no harness today needs a different argv shape.
- Codex-specific helpers (e.g., generating a `~/.codex/config.toml` block from harn config). Users configure codex separately; harn just exports the env var and selects the provider.
- Multiple simultaneous gateways for codex. Active gateway is one at a time, same as today.
