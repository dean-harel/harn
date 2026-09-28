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
   scripts keep working. The limit: a harness that cannot take a base URL from argv (pi and
   hermes, pending verify-first item 2) swaps only among providers its own registry knows.

## Interface

```
harn <harness>                        # subscription: the harness's own login
harn <harness> gw [<model>]           # whatever the gw slot points at
harn <harness> local [<model>]        # whatever the local slot points at
harn <harness> <provider> [<model>]   # a named provider, for one-offs
harn <harness> ... --show             # print the environment and exec line, run nothing
harn <harness> ... -- <args>          # pass the rest to the harness unchanged

harn login <provider> [--workspace <id>] [--no-open]
harn logout <provider>
harn key <provider>                   # print the provider's key, for reuse by another command
harn config [init [--force] | edit]
harn --version
```

The first positional after the harness is a source when it names a slot, a provider or
`account`, and an error otherwise; a model always follows a source, including `account`, where
it becomes `--model <model>`. Slot names and `account` are reserved: a provider named `gw`,
`local` or `account` fails config loading with exit 2. The short mode flags (`-l` and friends)
are removed. Bare `harn config` prints the resolved config file, as today.

A missing model resolves in this order: the provider's `default_model`; for a launcher, no
`--model` at all, so the launcher shows its own picker; for an endpoint with no
`default_model`, exit 2 naming `providers.<name>.default_model`. Every endpoint in the shipped
template carries a `default_model`, so `harn claude gw` survives a swap between them.

Bare `harn <harness>` is valid only for a harness with `account: true`. For any other it exits 2:
`harn: pi has no subscription login; use gw, local or a provider`.

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
  to `ollama-cloud` changes no command. A slot's value is a provider name, or an object mapping
  harness names to providers with `"*"` as the fallback (`{"*": "ollama", "pi": "ollama-api"}`),
  for a harness the usual provider cannot serve.
- **`label`** (`api`, `local`) is descriptive: `--show` prints it so a user sees whether a run
  leaves the machine. The subscription case has no entry and prints `subscription`.
- **`harness.<h>.account: true`** marks a harness with its own login. Endpoint support follows
  from the wire; a launcher reports an unsupported harness itself.
- **Wire blocks** (`anthropic_wire`, `openai_wire`) each carry `base_url` and an optional
  `key_env`. `openai_wire` also carries `wire_api` (default `responses`).
- **`providers.<p>.harness_names.<h>`** (optional) is the name harness `h` knows provider `p` by,
  substituted for `{provider}` in `gw_argv`; it defaults to the provider's key. It exists for
  harnesses with a built-in provider registry (pi, hermes).
- `gw_argv` keeps its current contract with `{gw}` renamed `{provider}`; the other placeholders
  are `{model}`, `{base_url}`, `{key_env}` and `{wire_api}`.
- Every command-shaped field (`launcher`, `key_command`) is an argv array, so a path with a space
  survives.

`harn config init` writes the template above with no secrets and no organization-specific
values, and refuses to overwrite without `--force`.

## Provider kinds

Every kind starts from the same clean environment, which is what makes switching clean: before
anything else, harn unsets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `OPENAI_BASE_URL`, and every `key_env` any configured provider resolves to.
Each kind then sets only its own variables. `<args>` below is the passthrough after `--`,
always appended unchanged.

- **account** (the no-source case, `account: true` harnesses only). Exec
  `<binary> [--model <model>] <args>`.
- **Claude settings files.** On every run of a harness with the anthropic wire, account or
  endpoint, warn without failing when `~/.claude/settings.json`, `.claude/settings.json` or
  `.claude/settings.local.json` in the working directory sets any of the variables above under
  `env`, since a settings file overrides the shell.
- **endpoint**. Resolve the credential, then:
  - anthropic wire: set `ANTHROPIC_BASE_URL` to `anthropic_wire.base_url`, the key in
    `anthropic_wire.key_env` (default `ANTHROPIC_AUTH_TOKEN`, a bearer token; the direct API
    uses `ANTHROPIC_API_KEY`), and the other of those two to the empty string, as the current
    code and Ollama's Claude Code instructions do; then exec `<binary> --model <model> <args>`.
  - openai wire: set the key in `openai_wire.key_env`, defaulting to the provider name
    uppercased with every character outside `[A-Z0-9_]` turned into `_`, plus `_API_KEY`
    (`ollama-cloud` gives `OLLAMA_CLOUD_API_KEY`), then exec `<binary> <gw_argv...> <args>`.
  - A provider without the wire block the harness needs (`harn codex anthropic`, where
    `anthropic` has no `openai_wire`) exits 2 naming `providers.<p>.openai_wire.base_url`.
  - A harness whose `gw_argv` has no `{base_url}` (pi, hermes) reaches only providers its own
    registry knows by `harness_names`. harn cannot verify that registry, so it passes the name
    through and the harness reports an unknown one.
- **launcher**. Exec `<launcher...> <harness> [--model <model>] [-- <args>]`. The launcher owns
  model download, context size and any harness profile it writes. Ollama is the only one.

Rule for adding a source: wire it as an endpoint, and use a launcher only where the tool manages
runtime state harn should not own.

## Credentials

An endpoint declares exactly one of:

- **`login: "openrouter-pkce"`**. `harn login openrouter [--workspace <id>]` runs OpenRouter's
  headless PKCE flow:
  1. Verifier: `openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n'`, 64 base64url characters
     (RFC 7636 allows 43 to 128).
  2. Challenge: `printf %s "$verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr
     '+/' '-_' | tr -d '='`.
  3. URL: `https://openrouter.ai/auth?code_challenge=<challenge>&code_challenge_method=S256&
     key_label=harn-<hostname>`, plus `&required_workspace_id=<id>` when `--workspace` is given.
     harn prints it and opens it with `open` or `xdg-open` when present, unless `--no-open` is
     given.
  4. The user pastes the code the page displays. It is single-use and expires in 10 minutes.
  5. Exchange: `curl -sS --fail-with-body -X POST https://openrouter.ai/api/v1/auth/keys -H
     'Content-Type: application/json' --data @-`, with the body
     `{"code": ..., "code_verifier": ..., "code_challenge_method": "S256"}` built by `jq` and
     written to curl's stdin, so neither value reaches argv. The key is the response's `key`
     field; a missing or empty `key` exits 2 with the response's error message.
  `--workspace` locks the key into that workspace server-side.
- **`login: "paste"`**. `harn login <provider>` reads the key once from a hidden prompt
  (`read -rs`).
- **`key_command`**. Any argv whose stdout is the key (`["op","read","op://..."]`,
  `["printenv","OLLAMA_API_KEY"]`). No login step.

**Key store.** Each key is one item named service `harn`, account `<provider>`: a generic
password in the keychain, a libsecret item with attributes `service=harn` and
`provider=<provider>`, or the file below. `harn login` probes the backends in this order and
writes to the first that passes; probes run only at login:

1. **macOS keychain**, through `security`. Its probe is a write, read and delete of a throwaway
   item, with the write made without the value on argv. If verify-first item 3 finds no such
   write, this backend is left out of 1.0 and macOS uses the file.
2. **libsecret**, through `secret-tool`, which reads the secret from stdin. Its probe is the
   same round trip, which fails when no secret service is running.
3. **A file** at `${XDG_STATE_HOME:-~/.local/state}/harn/keys/<provider>`, created under `umask
   077`. Always available.

A read, from `harn key` or from an endpoint run, searches the backends in the same order without
probing and takes the first item found, so a key stays reachable when a backend's availability
changes. No item found exits 2 naming `harn login <provider>`. `harn logout` deletes the item
from every backend. For a `key_command` provider, `harn key` runs the command and prints its
output.

**Where a key may go.** A key reaches a harness only through its environment: never argv, never
written outside the store, and never printed, with one exception: `harn key`, which exists to
hand the key to another command's stdin or `key_command`. `--show` does not resolve credentials
and prints `<redacted: login openrouter-pkce>`, `<redacted: login paste>` or
`<redacted: key_command op read ...>` in the key's place.

## Repository and release

The bar is a high-end open source agentic tool (pi, `earendil-works/pi`) and the UNIPaaS org
conventions as `UNIPaaS/gates` records them, so the repo can be adopted by the team unchanged.

- **Shape.** One executable `bin/harn`, bash 3.2-compatible (macOS `/bin/bash`): no `mapfile`,
  no associative arrays, empty arrays expanded as `${a[@]+"${a[@]}"}` under `set -u`.
- **Dependencies.** `jq`, `curl` and `openssl`. macOS ships all three (`jq` as `/usr/bin/jq`
  on current releases); minimal Linux images can lack `jq` and `curl`. The Homebrew formula
  declares `jq` and `curl`, and harn checks for all three before first use and names the
  install command for a missing one.
- **Files.** `README.md` (positioning first), `AGENTS.md` with `CLAUDE.md` symlinked to it,
  `CONTRIBUTING.md` stating the minimal core, `SECURITY.md` with the trust boundary (the user's
  own config, environment and store are inside it) and private reporting through GitHub Security
  Advisories, `CHANGELOG.md`, issue templates. Specs and plans live in `.agents/specs/` and
  `.agents/plans/`.
- **CI.** The test suite on `ubuntu-latest` and on `macos-latest` under `/bin/bash`;
  `shellcheck`; a Conventional Commits PR-title check. Actions pinned by commit hash with a
  version comment, `permissions: {}` by default, `persist-credentials: false`.
- **Releases.** release-please on `main`, one immutable semver tag stream, a `simple` release
  type. Merging the release PR is the human step that publishes. The version lives in one line
  of `bin/harn`, `HARN_VERSION="x.y.z" # x-release-please-version`, which release-please
  rewrites through `extra-files`; `harn --version` prints it. The release job alone is granted
  `contents: write` and `pull-requests: write` at job level; every other job keeps
  `permissions: {}`. The release uploads its source
  tarball and `SHA256SUMS`, then updates the formula in `dean-harel/homebrew-tap` from the same
  workflow, since a release created by `GITHUB_TOKEN` triggers no other workflow. The tap write
  uses a fine-grained token scoped to that repository with `contents: write` and an expiry,
  stored as `HOMEBREW_TAP_TOKEN`.
- **Install.** `brew install dean-harel/tap/harn` on macOS and Linux, or clone a tag and symlink
  `bin/harn` onto the `PATH`.
- **Exit codes.** 2 for a usage or config error, 3 for an internal error, otherwise the
  harness's own. Every error names the field or command to fix.

## Testing

Nothing in the suite launches a harness or reaches the network.

- The existing dry-run cases, rewritten in bash against the new grammar and rules. Cases for
  removed behaviour (short mode flags, a key printed by `--show`) are deleted, and their
  replacements are the cases below.
- Clean switching: with every variable in the clean list exported, each kind's `--show` output
  unsets all of them and sets only its own.
- `--show` never resolves a credential: a `key_command` that writes a marker file leaves no
  marker, and a sentinel key never appears in output.
- Key variable names: `ollama-cloud` resolves to `OLLAMA_CLOUD_API_KEY`, and the export succeeds
  under `/bin/bash`.
- PKCE: the challenge for RFC 7636 Appendix B's verifier
  (`dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk`) equals its published challenge
  (`E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`); a generated verifier is 64 characters of
  `[A-Za-z0-9_-]`. The exchange runs against a stub `curl` on `PATH` that records its argv and
  stdin: the test asserts the URL and method, that stdin carries the pasted code, the verifier
  and `S256`, that neither appears in argv, and that the returned `key` is stored. A response
  without `key` exits 2. The test passes `--no-open`, and a stub `open` and `xdg-open` on `PATH`
  fail the test if called.
- The file key store: mode `0600`, round trip, logout removes it.
- Slot swap: re-pointing `gw` from `openrouter` to `ollama-cloud`, compared by `--show` line:
  - claude: `ANTHROPIC_BASE_URL`, the redaction text and the default `--model` change; the key
    variable (`ANTHROPIC_AUTH_TOKEN`), the binary and the passthrough stay.
  - codex: the provider name inside every `gw_argv` token, `{base_url}`, the key variable
    (`OPENROUTER_API_KEY` to `OLLAMA_CLOUD_API_KEY`), the redaction text and the default model
    change; the binary and the passthrough stay.
  - In both, no value from `openrouter` remains anywhere in the output.
- Missing models: an endpoint without `default_model` exits 2 naming the field; a launcher
  without a model execs with no `--model`.
- Bare `harn pi` exits 2 with the no-subscription message.
- By hand, on each platform before a release, for the keychain and libsecret backends: `harn
  login` with a paste stores a key, `harn key` prints the same value, `harn logout` then makes
  `harn key` exit 2, and no key appears in `ps` output during the login.

## Deferred

Each waits for a concrete need.

- Model aliases across providers (`coder` mapping to one id per provider).
- A `cloud` kind for Bedrock or Vertex, where the credential is a cloud identity.
- Layered config (machine, project, home) and a team policy layer.
- Launch-time model validation against a provider's catalog.
- A retention notice for providers that do not enforce zero data retention.

## Verify first

Unknowns that could change the design, in the order implementation should settle them. Each
names what happens if the answer is no.

1. Whether `ollama launch` supports `pi` and `hermes`. If not, the template adds an
   `ollama-api` endpoint (`anthropic_wire.base_url` `http://localhost:11434`,
   `openai_wire.base_url` `http://localhost:11434/v1`, `key_command: ["printf", "ollama"]`,
   `default_model` `qwen3-coder`) and sets `slots.local` to `{"*": "ollama", "pi": "ollama-api", "hermes":
   "ollama-api"}`.
2. Whether pi and hermes can be pointed at a base URL from argv. If yes, their `gw_argv` gains
   `{base_url}` and swaps work for any provider. If not, they reach only providers their
   registry knows, through `harness_names`, and the README says so.
3. A way to write a keychain item without the secret on argv (`security -i` reading its command
   from stdin is the candidate). If none, macOS uses the file backend in 1.0.
4. That OpenRouter's headless flow with `required_workspace_id` returns a key bound to that
   workspace, checked with one real login. If not, `--workspace` is removed and the README tells
   members which workspace to pick.

## Migration

1.0.0 drops `active`, `gateway`, `local`, `secrets`, `key_ref`, `supports`, `harness.<h>.default`
and `gateway.<n>.key_env`. The changelog maps each:

- `active.gateway` becomes `slots.gw`, and `active.local` becomes `slots.local`.
- `gateway.<n>` becomes a `providers.<n>` entry of kind `endpoint`, and its `key_env` moves to
  `openai_wire.key_env`, the only wire the old field applied to.
- `key_ref` plus `secrets.<scheme>.command` always becomes `key_command`: the command string
  split on whitespace, then the `key_ref` appended (`"op read"` and `op://...` become
  `["op","read","op://..."]`). Switching that provider to a `login` afterwards is optional.
- `{gw}` inside any `harness.<h>.gw_argv` becomes `{provider}`.
- `local.<n>.launcher` becomes a `launcher` provider, its string split on whitespace
  (`"ollama launch"` becomes `["ollama","launch"]`).
- `supports` becomes `account: true` only where it listed `account`.
- `harness.<h>.default` goes: no source always means the subscription, and a user who defaulted
  to `gw` or `local` types the slot.
- The install changes: remove the `source .../lib/harn.zsh` line from the shell startup file
  and install `bin/harn` as above. For the 1.x releases, `lib/harn.zsh` stays as a stub that
  defines nothing and prints that instruction to stderr, so an old startup file keeps working
  and says what to change.
