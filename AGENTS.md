# harn

Unified launcher for AI coding harnesses (Claude Code, Codex, Pi, and more).
A single sourced zsh function that, given a harness and a mode, resolves config
and execs the right binary with the right environment. macOS + zsh only;
requires `jq`.

## Run

    harn claude               # default mode (from config)
    harn claude gw model      # route through a gateway
    harn claude local qwen    # local model
    harn codex gw openai/gpt-4o
    harn <h> -- <args>        # everything after -- is passed through
    harn <h> --show           # print the would-be exec line, run nothing
    harn config init|edit     # manage ~/.config/harn/config.json

The tool is a shell function sourced from `lib/harn.zsh`. After editing that
file, re-source it or open a new terminal.

## Test

    zsh tests/dry-run.sh

The dry-run suite points `HARN_CONFIG` at `lib/config.template.json`, so it
never depends on the user's live config. Use `--show` on any command to verify
the exec line without launching anything. Keep tests passing before commit.

## Architecture

All logic lives in `lib/harn.zsh`. Helper functions named `_harn_*` read the
JSON config through `jq` (`_harn_read_config`, `_harn_harness_default`,
`_harn_harness_supports`, `_harn_harness_wire`); `_harn_parse` and
`_harn_resolve_mode` turn argv into the `_A_*` state the launcher execs from.
Config is `~/.config/harn/config.json` (or `$XDG_CONFIG_HOME/harn`), overridable
with `$HARN_CONFIG`; the shipped template is `lib/config.template.json`.

Modes: `account` execs the harness against its own login and unsets wire env
vars that could redirect the session; `gw` resolves a key and injects env per
the harness wire protocol; `local` dispatches to a configured launcher. Adding
a harness is a config entry, not new code, unless it needs a new wire protocol.

## Conventions

Personal repo: author is `dean-harel <anichego@gmail.com>`, SSH remote, and no
`Co-Authored-By` or attribution trailers in commits. Secrets live in 1Password
and are referenced by config; never hardcode them.
