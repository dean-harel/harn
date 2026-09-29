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
config. MIGRATION.md maps the legacy config. lib/harn.zsh is a stub for startup files from the zsh-function era. Formula/harn.rb makes
the repository its own Homebrew tap. Specs and plans are in .agents/.

## Conventions

Conventional Commits; release-please cuts releases from main. No attribution lines anywhere.
