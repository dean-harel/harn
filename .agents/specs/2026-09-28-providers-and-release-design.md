# Providers, credentials and a production release

Status: in review (design phase)

## Goal

Make harn a tool a team can adopt: one command for any harness against a subscription, a
gateway API or a local model, with credentials handled, released and installable on macOS and
Linux. This is release 1.0.0 and breaks the current config schema.

## Value

Four promises, each one a test the design must pass:

1. **One way to say it.** `harn <harness> [<source>] [<model>]`, whatever the harness and the
   source.
2. **Clean switching.** Moving between subscription, gateway and local never inherits the
   previous session's environment.
3. **Credentials handled.** harn obtains, stores and passes keys; nobody pastes a key into a
   dotfile, and no secret manager is assumed.
4. **Swappable sources.** Changing gateway or local runtime is a config edit; habits and
   scripts keep working.

## Interface

```
harn <harness>                        # subscription: the harness's own login
harn <harness> gw [<model>]           # whatever the gw slot points at
harn <harness> local [<model>]        # whatever the local slot points at
harn <harness> <provider> [<model>]   # a named provider, for one-offs
harn <harness> ... --show             # print the environment and exec line, run nothing
harn <harness> ... -- <args>          # pass the rest to the harness unchanged

harn login <provider> [--workspace <id>]
harn logout <provider>
harn key <provider>                   # print the stored key, for key_command reuse
harn config [init [--force] | edit]
harn --version
```

The first positional after the harness is a source when it names a slot, a provider or
`account`, and an error otherwise; a model always follows a source. A missing model uses the
provider's `default_model`, so `harn claude gw` survives a gateway swap. The short mode flags
(`-l` and friends) are removed.

## Config

One file, `$HARN_CONFIG` or `${XDG_CONFIG_HOME:-~/.config}/harn/config.json`.

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
      "anthropic_wire": { "base_url": "https://ollama.com" },
      "openai_wire": { "base_url": "https://ollama.com/v1", "wire_api": "responses" }
    },
    "anthropic": {
      "kind": "endpoint",
      "label": "api",
      "login": "paste",
      "anthropic_wire": { "base_url": "https://api.anthropic.com", "key_env": "ANTHROPIC_API_KEY" }
    },
    "ollama": { "kind": "launcher", "label": "local", "launcher": ["ollama", "launch"] }
  },
  "harness": {
    "claude": { "wire": "anthropic", "binary": "claude", "account": true },
    "codex":  { "wire": "openai", "binary": "codex", "account": true,
                "gw_argv": ["-c", "model_providers.{provider}.name={provider}",
                            "-c", "model_providers.{provider}.base_url={base_url}",
                            "-c", "model_providers.{provider}.env_key={key_env}",
                            "-c", "model_providers.{provider}.wire_api={wire_api}",
                            "-c", "model_provider={provider}", "--model", "{model}"] },
    "pi":     { "wire": "openai", "binary": "pi", "gw_argv": ["--provider", "{provider}", "--model", "{model}"] },
    "hermes": { "wire": "openai", "binary": "hermes", "gw_argv": ["chat", "--provider", "{provider}", "--model", "{model}"] }
  }
}
```

- **Slots** are the user's categories and the swap point. Re-pointing `gw` from `openrouter`
  to `ollama-cloud` changes no command.
- **`label`** (`subscription`, `api`, `local`) is descriptive: docs and `--show` print it so a
  user sees whether a run leaves the machine and who bills it.
- **`harness.<h>.account: true`** replaces the `supports` list; endpoint support follows from
  the wire, and a launcher reports unsupported harnesses itself.
- `gw_argv` keeps its current contract with `{gw}` renamed `{provider}`.
- Every command-shaped field (`launcher`, `key_command`) is an argv array, so a path with a space
  survives.

`harn config init` writes the template above with no secrets and no organization-specific
values, and refuses to overwrite without `--force`.

## Provider kinds

Each kind owns its environment, which is what makes switching clean.

- **account** (implicit, the no-source case). Unset the wire's variables
  (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`; or `OPENAI_API_KEY`,
  `OPENAI_BASE_URL`) and exec the binary. Warn, without failing, when `~/.claude/settings.json`
  sets any of those under `env`, since a settings file overrides the shell.
- **endpoint**. Resolve the credential, then exec with the wire's variables:
  - anthropic wire: `ANTHROPIC_BASE_URL`, the key in `key_env` (default `ANTHROPIC_AUTH_TOKEN`,
    bearer; `ANTHROPIC_API_KEY` for the direct API), the other one set empty, then
    `<binary> --model <model>`.
  - openai wire: the key in `key_env` (default `<UPPER(provider)>_API_KEY`), then
    `<binary> <gw_argv...>`.
- **launcher**. Exec `<launcher...> <harness> --model <model> [-- <args>]`. The launcher owns
  model download, context size and any harness profile it writes. Ollama is the only one.

Rule for adding a source: wire it as an endpoint, and use a launcher only where the tool manages
runtime state harn should not own.

## Credentials

An endpoint declares exactly one of:

- **`login: "openrouter-pkce"`**. `harn login openrouter [--workspace <id>]` runs OpenRouter's
  headless PKCE flow: a verifier from `openssl rand`, an S256 challenge from `openssl dgst
  -sha256` in base64url, the URL `https://openrouter.ai/auth?code_challenge=...&
  code_challenge_method=S256&key_label=harn-<hostname>` plus `required_workspace_id` when given,
  opened with `open` or `xdg-open` and always printed. The user pastes the displayed code; `curl`
  posts it with the verifier to `https://openrouter.ai/api/v1/auth/keys`. The code is single-use
  and expires in 10 minutes. `--workspace` locks the key into that workspace server-side.
- **`login: "paste"`**. `harn login <provider>` reads the key once from a hidden prompt.
- **`key_command`**. Any argv whose stdout is the key (`["op","read","op://..."]`,
  `["printenv","OLLAMA_API_KEY"]`). No login step.

Stored keys go to the first available backend, keyed by provider name: the macOS keychain
(`security`), libsecret (`secret-tool`, which reads the secret from stdin), or a file at
`${XDG_STATE_HOME:-~/.local/state}/harn/keys/<provider>` created under `umask 077`.
`harn key <provider>` reads it back; `harn logout` deletes it.

A key travels only in the harness's environment: never argv, never printed, never written
outside the store. `--show` does not resolve credentials and prints
`<redacted: login openrouter-pkce>` or `<redacted: key_command op read ...>` in the key's place.

## Repository and release

The bar is a high-end open source agentic tool (pi, `earendil-works/pi`) and the UNIPaaS org
conventions as `UNIPaaS/gates` records them, so the repo can be adopted by the team unchanged.

- **Shape.** One executable `bin/harn`, bash 3.2-compatible (macOS `/bin/bash`): no `mapfile`,
  no associative arrays, empty arrays expanded as `${a[@]+"${a[@]}"}` under `set -u`. `jq`,
  `curl` and `openssl` are the dependencies; all three ship with or are standard on both
  platforms. `lib/harn.zsh` and its `source` line are removed.
- **Files.** `README.md` (positioning first), `AGENTS.md` with `CLAUDE.md` symlinked to it,
  `CONTRIBUTING.md` stating the minimal core, `SECURITY.md` with the trust boundary (the user's
  own config, environment and store are inside it) and private reporting through GitHub Security
  Advisories, `CHANGELOG.md`, issue templates. Specs and plans live in `.agents/specs/` and
  `.agents/plans/`.
- **CI.** The test suite on `ubuntu-latest` and on `macos-latest` under `/bin/bash`;
  `shellcheck`; a Conventional Commits PR-title check. Actions pinned by commit hash with a
  version comment, `permissions: {}` by default, `persist-credentials: false`.
- **Releases.** release-please on `main`, one immutable semver tag stream, a `simple` release
  type. A release uploads its source tarball and `SHA256SUMS`, then updates the formula in
  `dean-harel/homebrew-tap` from the same workflow, since a release created by `GITHUB_TOKEN`
  triggers no other workflow. The tap write uses a fine-grained token scoped to that repository
  with `contents: write` and an expiry, stored as `HOMEBREW_TAP_TOKEN`.
- **Install.** `brew install dean-harel/tap/harn` on macOS and Linux, or clone a tag and symlink
  `bin/harn` onto the `PATH`.
- **Exit codes.** 2 for a usage or config error, 3 for an internal error, otherwise the
  harness's own. Every error names the field or command to fix.

## Testing

Nothing in the suite launches a harness or reaches the network.

- The existing dry-run cases, ported to bash and to the new grammar.
- `--show` never resolves a credential: a `key_command` that writes a marker file leaves no
  marker, and a sentinel key never appears in output.
- PKCE: the challenge for RFC 7636 Appendix B's verifier equals its published challenge; the
  exchange runs against a stub `curl` on `PATH` and stores the returned key.
- The file key store: mode `0600`, round trip, logout removes it. The keychain and libsecret
  backends are checked by hand on each platform before a release.
- Slot swap: re-pointing `gw` changes the exec line and nothing else.

## Deferred

Each waits for a concrete need.

- Model aliases across providers (`coder` mapping to one id per provider).
- A `cloud` kind for Bedrock or Vertex, where the credential is a cloud identity.
- Layered config (machine, project, home) and a team policy layer.
- Launch-time model validation against a provider's catalog.
- A retention notice for providers that do not enforce zero data retention.

## Verify first

Unknowns that could change the design, in the order implementation should settle them:

1. Whether `ollama launch` supports `pi` and `hermes`. If not, those harnesses reach local
   models through an endpoint entry on `http://localhost:11434`.
2. Whether pi and hermes accept a `--provider` they do not ship with (`ollama-cloud`). If not,
   the provider entry carries the harness-side provider name.
3. A way to write a keychain item without the secret on argv (`security -i` reading its command
   from stdin is the candidate).
4. That OpenRouter's headless flow with `required_workspace_id` returns a key bound to that
   workspace, checked with one real login.

## Migration

1.0.0 drops `active`, `gateway`, `local`, `secrets`, `key_ref` and `supports`. The changelog
maps each: `active.gateway` becomes `slots.gw`, a gateway becomes a `providers` entry of kind
`endpoint`, `key_ref` plus `secrets` becomes `key_command` or a `login`, `local.<name>` becomes a
`launcher` provider and `slots.local`, and `supports` becomes `account: true`.
