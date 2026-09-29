# Migrating from the zsh function

harn 0.1.0 replaces the sourced zsh function with the `bin/harn` executable and a new config
schema. harn refuses a legacy config (one with `active` or `gateway` and no `providers`) with
exit 2 and points here.

The quickest path is a fresh config: back up the old file, run `harn config init --force`, then
carry your providers across. To convert by hand, 0.1.0 drops `active`, `gateway`, `local`,
`secrets`, `key_ref`, `supports`, `harness.<h>.default` and `gateway.<n>.key_env`:

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
  and install `bin/harn` as the README describes. Through the 0.x releases, `lib/harn.zsh` stays as a stub that
  defines nothing and prints that instruction to stderr, so an old startup file keeps working
  and says what to change.
