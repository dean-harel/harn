# Positioning and configuration principles

Status: in review (design phase)

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

### Login options

A login method is how harn obtains a key, and the extension point for a gateway that creates keys
itself. `login` takes an object form alongside the string form, which means the method with no
options:

```json
"login": { "method": "openrouter-pkce", "workspace": "<workspace uuid>" }
```

- Each method declares the options it accepts. Config loading exits 2 naming
  `providers.<p>.login.<option>` for an option its method does not accept.
- Options exist only where the method creates the key, since that is when the client chooses the
  key's scope (principle 5).
- `--show` prints the options in the redaction: `<redacted: login openrouter-pkce, workspace <uuid>>`.

| Method | Options |
| --- | --- |
| `paste` | none |
| `openrouter-pkce` | `workspace`: adds `required_workspace_id=<uuid>` to the authorization URL, so OpenRouter creates the key in that workspace and locks the page's workspace picker |

A gateway whose login creates keys, through an OAuth device or PKCE flow, adds a method with its own
options. A gateway whose keys come from its dashboard uses `paste` or `key_command` and needs no
code.

### The retention declaration

An optional `retention` string on an endpoint provider records what the operator declares about
the provider's data retention, in the operator's words, as the skill's field does
(`"zero, by the workspace guardrail"`). `--show` prints `retention: <text>` for an endpoint run, or
`retention: not declared`. harn enforces nothing from it.

### Onboarding a team to a gateway

Every gateway onboards the same way: the team's gateway is a provider entry, `gw` points at it, and
each member logs in once.

```bash
harn config init           # the template ships openrouter, ollama-cloud, anthropic and ollama
harn config edit           # when the team's gateway is another provider, or needs login options
harn login <provider>
harn claude gw
```

- The template points `gw` at OpenRouter, the gateway being onboarded today. A team on Ollama
  Cloud points `gw` at `ollama-cloud` and logs in with its key.
- A gateway missing from the template is one endpoint entry: base URLs for its wires, a
  `default_model`, and `login: "paste"` or a `key_command`.
- On OpenRouter, a member of several workspaces adds `login.workspace` before logging in. The
  team's member how-to carries the id; harn carries nothing team-specific.

## Deferred

Each has the trigger that brings it in.

- **An accounts section inside one file**, AWS-profile style, with `--account`, `HARN_ACCOUNT` and
  `default_account`. Trigger: a second person needs PKCE logins in two accounts, someone keeps
  three or more config files, or the duplicated `harness` section drifts between files.
- **A key store scoped per config file.** Today every file shares `keys/<provider>`, so two files
  using a PKCE login under one provider name share one key. Trigger: the first person who hits it.
  A `key_command` provider never touches the store.
- **Prebuilt binaries** through `goreleaser`, with checksums, for installs outside Homebrew and
  `go install`. Trigger: a Windows user, or a member without Homebrew or Go.
- **A keychain key store** through `zalando/go-keyring`, the library GitHub's, Stripe's and
  Doppler's CLIs share. Trigger: someone needs a store other than a 0600 file.

Vendor presets, built-in defaults per vendor, are out: they would put vendor knowledge into the
core, against principle 2.

## Implementation

**Language by kind of software.** Skills and services are TypeScript: they run inside an agent's
runtime or the team's stack and ship as source. Standalone CLIs are Go: they run before any
agent, from any project directory, installed by people, and must be self-contained. harn is a
standalone CLI, so harn is Go, the language most provider CLIs converged on (GitHub `gh`,
Stripe, Fly, Doppler, Terraform). It is likely the UNIPaaS org's first Go codebase.

- **Process handover.** `syscall.Exec` replaces harn with the harness on macOS and Linux, so the
  harness owns the terminal, its signals and its exit code. Windows is outside this release.
- **Dependencies.** The standard library covers HTTP, JSON, SHA-256 and random bytes, so the
  runtime needs for `jq`, `curl` and `openssl` go away. The one library is `tailscale/hujson`,
  which reads JSON with comments and trailing commas, the format adversarial-review's config
  already uses. Today's plain-JSON configs parse unchanged.
- **Command line.** Parsed by hand against the grammar in the providers spec, which stays
  unchanged. Harness and provider names come from config, which fits a command framework's fixed
  subcommand tree poorly.
- **Install.** The Homebrew formula builds from the git tag (`depends_on "go" => :build`), so a
  release still needs no uploaded asset; `go install github.com/dean-harel/harn@<tag>` works for
  anyone with Go.
- **Version.** One marked constant in the Go source, rewritten by release-please as the bash
  script's line is today.
- **Tests.** The 145 black-box checks in `tests/` run against the built binary unchanged and are
  the acceptance suite for the port. Go unit tests cover logic worth testing from inside, such as
  the PKCE vector from RFC 7636. CI adds `go vet` and a `gofmt` check to the existing matrix.

