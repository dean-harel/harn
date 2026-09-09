# harn

Unified launcher for AI coding harnesses (Claude Code, Codex, Pi, Hermes Agent, ...).

> Personal utility, shared in case it's useful. macOS + zsh only. No support promised.

```bash
harn claude              # account mode (default)
harn claude gw model     # via gateway
harn claude local qwen   # local model
harn codex gw openai/gpt-4o
harn hermes gw openai/gpt-4o
```

## Install

```bash
git clone git@github.com:dean-harel/harn.git /path/to/harn
echo 'source /path/to/harn/lib/harn.zsh' >> ~/.zshrc
```

Requires `jq`. The script is sourced into your shell; after editing it, re-source or open a new terminal. `--show` on any command prints the would-be exec line without running it. `zsh tests/dry-run.sh` runs the dry-run test suite.

## Modes

- **`account`** — exec the harness against its own subscription/auth (e.g. `claude` ChatGPT-style login or `codex` ChatGPT auth). Wire-specific env vars that could redirect the session (`ANTHROPIC_*` for anthropic, `OPENAI_API_KEY`/`OPENAI_BASE_URL` for openai) are unset before exec.
- **`gw`** — route through a configured gateway: resolve a key, inject env vars per the harness's wire protocol, exec.
- **`local`** — dispatch to a configured launcher (e.g. `ollama launch`) for a local model.

Default mode per harness is set in the config; `harn <h>` with no mode picks it up.

## Config

```bash
harn config init    # create ~/.config/harn/config.json from template
harn config edit    # open in $EDITOR
harn config         # print resolved config
```

Path: `~/.config/harn/config.json` (or `$XDG_CONFIG_HOME/harn/config.json`). Override with `HARN_CONFIG=/path/to/config.json`.

### Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "active": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "gateway": { "type": "string" },
        "local":   { "type": "string" }
      }
    },
    "secrets": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["command"],
        "properties": {
          "command": {
            "type": "string",
            "description": "Receives the full key_ref as $1; stdout is the secret."
          }
        }
      }
    },
    "gateway": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["key_ref"],
        "properties": {
          "key_ref": {
            "type": "string",
            "description": "<scheme>://<rest>; scheme selects a secrets entry."
          },
          "anthropic_wire": {
            "type": "object",
            "required": ["base_url"],
            "properties": {
              "base_url": { "type": "string", "format": "uri" }
            }
          },
          "openai_wire": {
            "type": "object",
            "required": ["base_url"],
            "properties": {
              "base_url": { "type": "string", "format": "uri" },
              "wire_api": { "type": "string", "description": "Default: \"chat\"." }
            }
          },
          "key_env": {
            "type": "string",
            "description": "openai-wire: env var name. Default: <UPPER(name)>_API_KEY."
          }
        }
      }
    },
    "local": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["launcher"],
        "properties": {
          "launcher": {
            "type": "string",
            "description": "Command prefix; harn appends <harness> --model <model> [-- ...]."
          }
        }
      }
    },
    "harness": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["wire", "binary", "supports"],
        "properties": {
          "wire":     { "enum": ["anthropic", "openai"] },
          "binary":   { "type": "string" },
          "supports": {
            "type": "array",
            "uniqueItems": true,
            "items": { "enum": ["account", "gw", "local"] }
          },
          "default":  { "enum": ["account", "gw", "local", null] },
          "gw_argv": {
            "type": "array",
            "items": { "type": "string" },
            "description": "openai-wire only: argv template for gw mode. Placeholders: {gw}, {model}, {base_url}, {key_env}, {wire_api}. Defaults to [\"--provider\", \"{gw}\", \"--model\", \"{model}\"]."
          }
        }
      }
    }
  }
}
```

Adding a harness, gateway, launcher, or secrets provider is a config edit only — no code changes. See `lib/config.template.json` for a working example.

## Gateway mode

When you run `harn <harness> gw <model>`:

1. Look up `gateway.<active.gateway>` → get `key_ref` and the wire-specific config.
2. Resolve `key_ref` via the secrets mechanism (below) → get the key.
3. Inject env vars based on the harness's `wire`:
   - **`anthropic`**: set `ANTHROPIC_BASE_URL` (from `gateway.<name>.anthropic_wire.base_url`) and `ANTHROPIC_AUTH_TOKEN` (key). Clear `ANTHROPIC_API_KEY` to force the gateway path.
   - **`openai`**: set `<KEY_ENV>=<key>` where `KEY_ENV` defaults to `<UPPER(gateway)>_API_KEY` or comes from `gateway.<name>.key_env`. Never put the key on argv (visible in `ps`).
4. Exec the harness binary. For openai-wire harnesses, argv is templated by `harness.<name>.gw_argv` with substitutions for `{gw}`, `{model}`, `{base_url}` (from `gateway.<name>.openai_wire.base_url`), `{key_env}`, and `{wire_api}` (from `openai_wire.wire_api`, default `"chat"`). Pi's template uses only `{gw}` and `{model}` because pi has a built-in provider registry; codex's template uses the full set so harn can inject the whole provider definition via `-c` overrides without needing `~/.codex/config.toml`. Hermes has a built-in registry too, so its template is the pi shape prefixed with the `chat` subcommand. Default template if unset is the pi shape.

Env vars die with the spawned process. Keys are never persisted to disk.

### Key resolution

`key_ref` has the form `<scheme>://<rest>`. The wrapper splits on `://`, looks up `secrets.<scheme>.command`, and runs `<command> <full-key_ref>` — stdout is the secret.

So with the default config:

| `key_ref`                       | `secrets.<scheme>.command` | Final command                          |
| ---                             | ---                        | ---                                    |
| `op://Vault/Item/credential`    | `op read`                  | `op read op://Vault/Item/credential`   |
| `env://OPENROUTER_API_KEY`      | (you supply a shim)        | `<your-shim> env://OPENROUTER_API_KEY` |
| `vault://path/to/secret`        | (you supply a wrapper)     | `<your-wrapper> vault://path/...`      |

The wrapper has no built-in knowledge of any specific secret store, no platform-specific credential integrations, no fallback handling — providers are entirely config-driven.

**Contract for a custom resolver:** receives the full `key_ref` as `$1`, prints the secret to stdout, exits 0 on success.

### Default `op` provider

The default config wires `op://` to bare `op read`. That means `op` itself must be authenticated when `harn` invokes it — typically via the 1Password desktop app's CLI integration (app open + unlocked, "Integrate with 1Password CLI" enabled in Settings → Developer). Verify with `op whoami`.

If `op whoami` fails, `harn claude gw …` will hang waiting for `op` to prompt. That's an `op` setup issue, not a `harn` issue.

## Local mode

`harn <harness> local <model>` execs `<launcher> <harness> --model <model> [-- <passthrough>]`, where the launcher comes from `local.<active.local>.launcher`. Any program fitting that argv shape works.

The configured launcher is responsible for any prerequisites (a running model server, tool-call translation, etc.); `harn` only formats the dispatch.

Whether the resulting harness/model combination is *usable* depends on two constraints, neither of which `harn` can help with:

- The model must support the harness's calling convention (typically: tool/function calling).
- The model must respond within the harness's request deadline. Tool-heavy coding harnesses can send ~100k-token prompts per turn, so weights + KV cache must fit fully on the available accelerator memory.

**Concrete example for the default config (`ollama launch`):** check `ollama show <model>` for `tools` capability, and on 32-48 GB Apple Silicon, ~20B-class models like `gpt-oss:20b` fit at full context. 30B+ models at 128k context typically spill onto CPU and time out. To raise a model's context window:

```bash
echo 'FROM <base>:latest\nPARAMETER num_ctx 131072' \
  | ollama create <base>-128k -f -
```

