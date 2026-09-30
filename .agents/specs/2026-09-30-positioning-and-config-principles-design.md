# Positioning and configuration principles

Status: in design. Two decisions are open, listed at the end.

## Positioning

harn is the vendor-neutral switchboard for AI coding harnesses: one command that moves between a
harness's own subscription, any gateway and a local model, with a clean environment on every
switch, in the open.

The neighbours each own one source. OpenRouter's Ori Harness launches twelve harnesses against
OpenRouter only, with a PKCE login and the workspace's guardrails; it is a TypeScript program
compiled with Bun and shipped as a closed-source binary. `ollama launch` does the same for Ollama's
local and cloud models. A working day moves across a subscription, a team gateway and sometimes a
local model, and harn is the one tool that covers all three with one grammar.

In a team, harn is the on-ramp when members are onboarded to a gateway such as OpenRouter. Its
case to a team is one habit across every source, the gateway included. It takes on governance only
where the gateway cannot enforce the rule itself; everything a gateway enforces inside a workspace
(model allowlists, budgets, zero-retention routing) stays with the gateway.

## Configuration principles

These five hold for harn and for the adversarial-review skill, which configures gateways for a
review panel. A new tool in the same family starts from them.

1. **Config holds references, never secrets.** A credential is a command given as argv
   (`key_command`), and its standard output is the key.
2. **Vendor knowledge lives at the edge.** The core is agnostic; vendor specifics sit in the
   shipped template or in adapters, never in core code. The one exception is a login method, which
   is a vendor's protocol by nature (`openrouter-pkce`).
3. **An account is a file**, chosen by an environment variable (`HARN_CONFIG`, the skill's
   `CFR_CONFIG`). A run is fully determined by its file, its environment and its flags; no command
   stores a current account or source for later runs.
4. **Named entries, a default in the file, a per-run override.** harn: `providers`, `slots`, the
   source on the command line. The skill: `gateway`, `active`, `CFR_PROFILE` and `--profile`.
5. **The client shows what the gateway enforces, and enforces only what the gateway cannot.** The
   skill prints the operator's retention declaration before an upload. harn pins the workspace a
   key is created in, because that choice happens at login, before any gateway rule applies.

Where the two tools differ on purpose:

- **`provider` and `gateway`.** A gateway is a role: a source that lists its models and declares
  its retention. A provider is any source, including a subscription or a local launcher.
- **A `kind` and an adapter program.** harn only sets environment variables for two kinds of
  source, which data describes. The skill parses catalogs, prices responses and groups findings,
  which takes code per gateway.
- **`slots` and profiles.** A slot can move between providers because each provider has a default
  model. A review profile names model ids that belong to one gateway, so it lives under that gateway.

## Applied to harn

### Accounts are files

A second account is a second config file. The shipped config is the everyday account; another is
reached with `HARN_CONFIG`, typically through a shell alias:

```bash
alias harnp='HARN_CONFIG=~/.config/harn/personal.json harn'
```

`--show` prints the config file in use on its first line (`config: <path>`), so every run shows
which account it used.

### The workspace pin

`login` takes an object form alongside the string form:

```json
"openrouter": {
  "kind": "endpoint",
  "login": { "method": "openrouter-pkce", "workspace": "<workspace uuid>" },
  ...
}
```

- `"login": "openrouter-pkce"` stays valid and means the object with no `workspace`.
- With `workspace`, `harn login` adds `required_workspace_id=<uuid>` to the authorization URL.
  OpenRouter then creates the key in that workspace and locks the page's workspace picker.
- `workspace` is accepted only with `openrouter-pkce`. On any other method, config loading exits 2
  naming `providers.<p>.login.workspace`, since only that login creates the key.
- `--show` prints the pin in the redaction: `<redacted: login openrouter-pkce, workspace <uuid>>`.

### The retention declaration

An optional `retention` string on an endpoint provider records what the operator declares about
the provider's data retention, in the operator's words, as the skill's field does
(`"zero, by the workspace guardrail"`). `--show` prints `retention: <text>` for an endpoint run, or
`retention: not declared`. harn enforces nothing from it.

### Team onboarding

A team's setup is one config file kept in the team's own repository, holding the team gateway with
its workspace pin and its retention declaration. harn itself carries nothing team-specific.

## Deferred

Each has the trigger that brings it in.

- **An accounts section inside one file**, AWS-profile style, with `--account`, `HARN_ACCOUNT` and
  `default_account`. Trigger: a second person needs PKCE logins in two accounts, someone keeps
  three or more config files, or the duplicated `harness` section drifts between files.
- **A key store scoped per config file.** Today every file shares `keys/<provider>`, so two files
  using a PKCE login under one provider name share one key. Trigger: the first person who hits it.
  A `key_command` provider never touches the store.
- **Comments in the config.** `jq` reads plain JSON only; comments come with the implementation
  language decision below.

Vendor presets, built-in defaults per vendor, are out: they would put vendor knowledge into the
core, against principle 2.

## Open decisions

1. **Implementation language.** The candidates, from a survey of eighteen CLIs:
   - Go, where most provider CLIs converged (GitHub `gh`, Stripe, Fly, Doppler, Terraform), with
     `cobra`, `goreleaser` and `zalando/go-keyring` in common. `syscall.Exec` hands the process to
     the harness. The current recommendation.
   - TypeScript compiled with Bun, the AI-tooling camp (Claude Code, Ori, opencode, and Supabase,
     which moved to it from Go). The team's language; a larger binary and a less mature process
     handover.
   - bash 3.2, today's implementation: no build, no Windows, no keychain without shelling out.

   The 145 black-box checks in `tests/` become the acceptance suite for any port.
2. **How a member installs the team's config file**: copied into place by hand, or
   `harn config init --from <file>`.
