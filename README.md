# harn

One command for any AI coding harness (Claude Code, Codex, Pi, Hermes Agent), against your
subscription, a gateway API or a local model.

## Where it fits

For OpenRouter alone, OpenRouter's own Ori Harness is the vendor-supported launcher. harn is for
switching between your subscription, one or more gateways and local models with one command, and
it keeps your keys out of dotfiles.

Every run starts from a clean environment: harn unsets every provider variable it knows before
setting the ones the chosen source needs, so a gateway session never leaks into a subscription
one.

## Install

With Homebrew, on macOS or Linux:

```bash
brew tap dean-harel/harn https://github.com/dean-harel/harn
brew install dean-harel/harn/harn
```

Or from a release tag:

```bash
git clone --branch vX.Y.Z git@github.com:dean-harel/harn.git ~/src/harn
ln -s ~/src/harn/bin/harn ~/.local/bin/harn
```

Requirements: `jq`, `curl` and `openssl`. macOS ships all three; on a minimal Linux image install
`jq`, `curl` and `openssl` with the package manager. harn names a missing one on first use.

## Use

```
harn <harness>                        # subscription: the harness's own login
harn <harness> gw [<model>]           # whatever the gw slot points at
harn <harness> local [<model>]        # whatever the local slot points at
harn <harness> <provider> [<model>]   # a named provider, for one-offs
harn <harness> ... --show             # print the environment and exec line, run nothing
harn <harness> ... -- <args>          # pass the rest to the harness unchanged

harn login <provider> [--no-open]
harn key <provider>                   # print the provider's key, for reuse by another command
harn config [init [--force] | edit]
harn --version
```

A missing model falls back to the provider's `default_model`, and a local launcher with no model
shows its own picker.

**First run through OpenRouter:**

```bash
harn config init
harn login openrouter      # opens OpenRouter in the browser; paste the code it shows
harn claude gw
```

**Swapping gateways.** Point the `gw` slot at another provider and every command keeps working:

```json
"slots": { "gw": "ollama-cloud", "local": "ollama" }
```

```bash
harn login ollama-cloud    # paste the key from ollama.com; input is hidden
harn claude gw
```

**A local model** through Ollama, which must be installed:

```bash
ollama pull qwen3-coder
harn claude local qwen3-coder
```

`--show` on any command prints what would run, with every key redacted, so it is safe to paste
into an issue.

## Config

One file, `$HARN_CONFIG` or `${XDG_CONFIG_HOME:-~/.config}/harn/config.json`. `harn config init`
writes the shipped template, [`lib/config.template.json`](lib/config.template.json), and
`harn config` prints the resolved file.

**Slots** are the swap point. `gw` and `local` each name one provider; changing a slot changes no
command. The names `gw`, `local` and `account` are reserved.

**Providers** come in two kinds. An `endpoint` is a base URL per wire (`anthropic_wire` for
Claude Code, `openai_wire` for Codex, Pi and Hermes) plus a credential and a `default_model`. A
`launcher` hands the harness to a tool that manages its own runtime, such as `ollama launch`,
which pulls the model, sets the context size and writes any harness profile it needs.

**Credentials.** An endpoint sets exactly one of:

- `"login": "openrouter-pkce"`: `harn login openrouter` runs OpenRouter's browser login and
  stores the key it returns. No key ever passes through your clipboard.
- `"login": "paste"`: `harn login <provider>` reads the key once from a hidden prompt.
- `"key_command"`: any command whose output is the key, written as a list of words, for example
  `["op", "read", "op://Private/OpenRouter/credential"]` for 1Password or
  `["printenv", "OLLAMA_API_KEY"]` for a variable you manage yourself. A native OpenRouter
  entry with a key you created in its dashboard works the same way.

**`harness_names`.** Pi and Hermes resolve a provider in their own registry. When a harness knows
a provider under another name, map it: a provider you called `or` reaches Pi with
`"harness_names": {"pi": "openrouter"}`.

## Where keys live

A key from `harn login` is one file per provider under
`${XDG_STATE_HOME:-~/.local/state}/harn/keys/`, readable only by you (mode 0600). `harn key
<provider>` prints it, so another tool can take it as its own `key_command`:
`["harn", "key", "openrouter"]`.

A key reaches a harness only through its environment, never its command line. To remove one,
delete its file and revoke the key on the provider's keys page
(`https://openrouter.ai/settings/keys` for OpenRouter); deleting the file alone leaves the key
valid. Logging in again overwrites the file.

## Limits

- Pi and Hermes take no base URL on the command line, so through `gw` they reach only providers
  their own registry knows. Claude Code and Codex reach any provider.
- Local models need Ollama installed; `ollama launch` pulls the model on first use.

## Upgrading from the zsh function

Remove the `source .../lib/harn.zsh` line from your shell startup file and install `bin/harn` as
above. The old config schema is refused with a pointer to [MIGRATION.md](MIGRATION.md), which
maps every field.

## Develop

```bash
/bin/bash tests/run.sh
bin/harn claude gw --show
```

The suite runs under macOS `/bin/bash` 3.2 and on Linux, never launches a harness and never
reaches the network. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
