# harn

A single Go binary that runs an AI coding harness against a subscription, a gateway API or a
local model. The standard library plus `tailscale/hujson` and `golang.org/x/term`.

## Run and test

    /bin/bash tests/run.sh              # builds .build/harn, then the black-box suite; needs Go and jq
    /bin/bash tests/run.sh t_endpoint   # one test file
    go test ./...                       # unit tests: quoting, config parsing, PKCE, the key store
    go vet ./... && gofmt -l .          # CI fails on any output from gofmt -l
    go run golang.org/x/vuln/cmd/govulncheck@v1.8.0 ./...   # known vulnerabilities reachable from harn

The black-box suite runs the binary as a child process against a temporary HOME, never launches a
real harness and never reaches the network. HARN_BIN points it at another binary. The test
scripts stay bash 3.2, since CI runs them under macOS /bin/bash.

## Invariants

- **A key never reaches argv or output.** It travels through the harness's environment only;
  --show prints a redaction and never resolves a credential. harn key is the one command that
  prints a key. A test pins each of these.
- **Every run clears before it sets.** cleanVars lists everything a run unsets; a new provider
  variable belongs there.
- **harn execs the harness.** syscall.Exec replaces the process, so the harness owns the terminal,
  its signals and its exit code.
- **Command-shaped config is an argv array.**
- **Vendor knowledge stays out of the core.** A login method is the exception, being a vendor's
  protocol. The configuration principles are in .agents/specs/2026-09-30-positioning-and-config-principles-design.md.

## Layout

One package at the root. main.go dispatches and holds the version; config.go loads the config and
embeds lib/config.template.json, which stays plain JSON because the tests edit it with jq; run.go
turns a source into an environment and an argv and execs it; quote.go quotes for --show;
credential.go resolves keys and owns the key store; login.go and pkce.go obtain keys;
configcmd.go is harn config. Specs and plans are in .agents/.

## Conventions

Conventional Commits; pull requests are squash-merged with the PR title as the commit message. harn is
installed from source (go install or a clone), so there are no releases. No attribution lines anywhere.
