# Go port and configuration principles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bash `bin/harn` with a Go binary that passes the black-box suite, then add the three configuration changes the positioning spec settles: the config file in `--show`, the retention declaration, and login options.

**Architecture:** One `package main` at the repository root, split by responsibility across `main.go`, `config.go`, `run.go`, `quote.go`, `credential.go`, `login.go`, `pkce.go` and `configcmd.go`. The existing bash suite in `tests/` runs against the built binary (`.build/harn`) and is the acceptance gate for every slice. Each slice ports one area until its test file passes, so the Go binary works end to end from the first task. The cutover task deletes the bash script once the whole suite passes on Go.

**Tech Stack:** Go (Homebrew's current `go`, 1.27.x), `github.com/tailscale/hujson`, `golang.org/x/term`; bash 3.2 and `jq` for the black-box suite only; release-please; a Homebrew formula building from the git tag; Docker, for shellcheck and the Linux run in Task 7.

**Spec:** `.agents/specs/2026-09-30-positioning-and-config-principles-design.md`, with the grammar and behaviour in `.agents/specs/2026-09-28-providers-and-release-design.md`. Where the two differ, the positioning spec's Implementation section wins: it replaces the providers spec's bash 3.2 shape and its `jq`, `curl` and `openssl` dependencies.

**Branch:** create `feat/go-port` from `docs/positioning` before Task 1.

## Global Constraints

- Go module `github.com/dean-harel/harn`, one package `main` at the repository root, so `go install github.com/dean-harel/harn@<tag>` works.
- Dependencies: the standard library, `github.com/tailscale/hujson` and `golang.org/x/term`, nothing else.
- macOS and Linux. `syscall.Exec` hands the process to the harness. Windows is outside this release.
- Exit codes: 2 for a usage or config error, 3 for an internal error, otherwise the harness's own. Every error names the field or command to fix, printed as `harn: <message>` followed by hints indented four spaces.
- The command-line grammar is unchanged from the providers spec.
- A key never reaches argv or output; `--show` never resolves a credential; `harn key` is the one command that prints a key.
- The config is JSON with comments and trailing commas (hujson). `lib/config.template.json` stays plain JSON, because the tests edit it with `jq`.
- The black-box suite runs under macOS `/bin/bash` 3.2 and Linux bash, never launches a real harness and never reaches the network.
- Markdown is ASCII only, with no personal names. Commits are Conventional Commits with no attribution lines.

## Review Focus

1. A passthrough argument holding a newline, a `$` or a backtick: the `--show` exec line must still paste into bash as the same argument (Task 1).
2. A missing binary, whether the harness or a `key_command`: exit 2 naming it, and a harness's own exit code passes through `exec` unchanged (Tasks 1 and 2).
3. A new login over a key file that already exists with a looser mode: the file ends at 0600 (Task 4).
4. A provider name, label, retention text or redaction holding a newline: `--show` comment lines stay single lines, so a paste cannot run an injected line (Task 8).
5. Degenerate configs: `{}` is a clean "unknown harness" error, comments and trailing commas parse, and invalid JSON exits 2 naming the file (Tasks 1 and 6).

---

### Task 1: Walking skeleton: the subscription path in Go

**Files:**
- Create: `go.mod`, `go.sum`, `main.go`, `config.go`, `run.go`, `quote.go`, `quote_test.go`, `config_test.go`
- Modify: `tests/run.sh` (whole file), `tests/lib.sh:3`, `tests/t_account.sh` (append), `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func die(code int, msg string, hints ...string)`, `func warn(msg string)`
  - `type Config struct { File, Source string; Raw []byte; Slots map[string]json.RawMessage; Providers map[string]Provider; Harness map[string]Harness }`
  - `type Provider struct { Kind, Label, Login string; KeyCommand []string; DefaultModel string; AnthropicWire, OpenAIWire *Wire; HarnessNames map[string]string; Launcher json.RawMessage }`
  - `type Wire struct { BaseURL, KeyEnv, WireAPI string }`, `type Harness struct { Wire, Binary string; Account bool; GwArgv []string }`
  - `func (p Provider) wire(name string) *Wire`
  - `func configPath() string`, `func loadConfig() *Config`, `func parseConfig(raw []byte) (*Config, error)`, `func displaySource(src string) string`, `func sortedKeys[V any](m map[string]V) []string`
  - `type invocation struct { harness, source, model string; show bool; pass []string }`
  - `type envVar struct { name, value, redaction string }`
  - `type plan struct { provider, label, kind string; env []envVar; argv []string }`, `func (p *plan) set(name, value string)`
  - `func run(cfg *Config, args []string)`, `func keyEnv(cfg *Config, wire, provider string) (string, error)`, `func cleanVars(cfg *Config) []string`
  - `func shellQuote(s string) string`
  - `tests/run.sh [t_name ...]` builds `.build/harn` and runs the named test files, or all of them; `HARN_BIN` points the suite at another binary.

- [ ] **Step 1: Install Go and start the module**

```bash
brew install go
go version
cd ~/Developer/personal/harn && git switch -c feat/go-port docs/positioning && go mod init github.com/dean-harel/harn
```

Expected: `go version go1.27.x darwin/arm64`, and `go: creating new go.mod: module github.com/dean-harel/harn`.

- [ ] **Step 2: Point the suite at the Go binary**

Replace `tests/run.sh` with:

```bash
#!/bin/bash
# Runs the suite under whatever bash invokes it; CI uses /bin/bash on macOS for 3.2.
# Usage: tests/run.sh [t_name ...]. Builds .build/harn first, unless HARN_BIN names a binary.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
# Built before lib.sh swaps HOME, so the build uses the real module cache.
if [ -z "${HARN_BIN:-}" ]; then
  (cd "$root" && go build -o .build/harn .) || { printf 'build failed\n'; exit 1; }
fi
# shellcheck source=tests/lib.sh
. "$root/tests/lib.sh"
files=()
if [ $# -eq 0 ]; then
  files=("$ROOT"/tests/t_*.sh)
else
  for n in "$@"; do files+=("$ROOT/tests/$n.sh"); done
fi
for t in "${files[@]}"; do
  # shellcheck disable=SC1090 # each test file in turn
  . "$t"
done
printf '%d passed, %d failed\n' "$T_PASS" "$T_FAIL"
[ "$T_FAIL" = 0 ]
```

In `tests/lib.sh`, replace line 3 (`HARN="$ROOT/bin/harn"`) with:

```bash
HARN="${HARN_BIN:-$ROOT/.build/harn}"
```

Append to `.gitignore`:

```
.build/
```

- [ ] **Step 3: Add the Review Focus checks to `tests/t_account.sh`**

Append:

```bash
# Review Focus 2: the harness's exit code is harn's own, since harn execs it.
stub claude 'exit 7'
OUT=$(PATH="$STUBS:$PATH" "$HARN" claude 2>&1); RC=$?
code "harness exit code passes through" "$RC" 7

# Review Focus 1: a newline, a dollar sign and a backtick survive the --show paste.
stub claude 'for a in "$@"; do printf "[%s]\n" "$a"; done'
run claude --show -- 'two
lines' '$HOME' '`id`'
line=$(printf '%s\n' "$OUT" | grep '^exec ')
pasted=$(PATH="$STUBS:$PATH" /bin/bash -c "${line#exec }")
has "--show line survives a paste (newline)" "$pasted" "[two
lines]"
has "--show line survives a paste (dollar)" "$pasted" '[$HOME]'
has "--show line survives a paste (backtick)" "$pasted" '[`id`]'

# Review Focus 5: an empty config is a clean config error.
em=$(mktemp); printf '{}' > "$em"
OUT=$(HARN_CONFIG="$em" "$HARN" claude --show 2>&1); RC=$?
code "empty config is a config error" "$RC" 2
has "empty config names the harness" "$OUT" "unknown harness 'claude'"

# Review Focus 2: a harness missing from PATH is named.
nb=$(cfgwith '.harness.claude.binary = "no-such-harness-binary"')
OUT=$(HARN_CONFIG="$nb" "$HARN" claude 2>&1); RC=$?
code "missing harness binary" "$RC" 2
has "missing binary is named" "$OUT" "'no-such-harness-binary' is not on PATH"
```

- [ ] **Step 4: Run the account checks to verify they fail**

Run: `/bin/bash tests/run.sh t_account`
Expected: `no Go files in ...` then `build failed`, exit 1.

- [ ] **Step 5: Write the failing unit tests**

`quote_test.go`:

```go
package main

import (
	"os/exec"
	"testing"
)

func TestShellQuoteRoundTripsThroughBash(t *testing.T) {
	cases := []string{"", "plain", "hello world", "it's", `back\slash`, "a\nb", "tab\there",
		"$HOME", "`id`", "semi;colon", "~user", "glob*?[x]", "caf\u00e9 \u2713",
		"https://openrouter.ai/api/v1", "!bang", "ctrl\x01char"}
	for _, s := range cases {
		out, err := exec.Command("/bin/bash", "-c", "printf '%s' "+shellQuote(s)).Output()
		if err != nil {
			t.Fatalf("%q: bash failed: %v", s, err)
		}
		if string(out) != s {
			t.Errorf("%q: bash read back %q from %s", s, out, shellQuote(s))
		}
	}
}

func TestShellQuoteMatchesBashPrintfQ(t *testing.T) {
	want := map[string]string{
		"":                                       "''",
		"hello world":                            `hello\ world`,
		"it's":                                   `it\'s`,
		"https://openrouter.ai/api":              "https://openrouter.ai/api",
		"model_providers.x.base_url=https://h/v1": "model_providers.x.base_url=https://h/v1",
	}
	for in, w := range want {
		if got := shellQuote(in); got != w {
			t.Errorf("shellQuote(%q) = %s, want %s", in, got, w)
		}
	}
}
```

`config_test.go`:

```go
package main

import "testing"

func TestParseConfigAcceptsCommentsAndTrailingCommas(t *testing.T) {
	raw := []byte(`{
  // the everyday account
  "slots": { "gw": "or", },
  "harness": { "claude": { "wire": "anthropic", "binary": "claude", "account": true, }, },
}`)
	c, err := parseConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	if !c.Harness["claude"].Account || c.Harness["claude"].Binary != "claude" {
		t.Errorf("harness not parsed: %+v", c.Harness)
	}
	if string(c.Raw) != string(raw) {
		t.Error("Raw must keep the file as written, comments included")
	}
}

func TestParseConfigRejectsInvalidJSON(t *testing.T) {
	if _, err := parseConfig([]byte(`{"slots": `)); err == nil {
		t.Error("want an error for truncated JSON")
	}
}
```

Run: `go test ./...`
Expected: FAIL, `undefined: shellQuote` and `undefined: parseConfig`.

- [ ] **Step 6: Write the implementation**

`main.go`:

```go
// Command harn runs an AI coding harness against a subscription, a gateway or a local model.
package main

import (
	"fmt"
	"os"
)

const version = "0.0.0-dev" // x-release-please-version

const usage = "usage: harn <harness> [<source>] [<model>] [--show] [-- <args>...]"

const helpText = `usage: harn <harness> [<source>] [<model>] [--show] [-- <args>...]

Sources:
  (none) or account     the harness's own subscription login
  gw, local             whatever that slot points at in the config
  <provider>            a named provider, for a one-off

Commands:
  harn login <provider> [--no-open]
  harn key <provider>          print the provider's key, for reuse by another command
  harn config                  print the config file
  harn config init [--force]   write the template config
  harn config edit             open the config in $EDITOR
  harn --version

Examples:
  harn claude
  harn claude gw
  harn codex gw openai/gpt-6-sol
  harn claude local qwen3-coder -- -p "hello"
  harn claude ollama-cloud --show
`

func main() {
	args := os.Args[1:]
	first := ""
	if len(args) > 0 {
		first = args[0]
	}
	switch first {
	case "--version":
		fmt.Printf("harn %s\n", version)
		return
	case "--help", "-h", "help":
		fmt.Print(helpText)
		return
	}
	run(loadConfig(), args)
}

func die(code int, msg string, hints ...string) {
	fmt.Fprintf(os.Stderr, "harn: %s\n", msg)
	for _, h := range hints {
		fmt.Fprintf(os.Stderr, "    %s\n", h)
	}
	os.Exit(code)
}

func warn(msg string) { fmt.Fprintf(os.Stderr, "harn: warning: %s\n", msg) }
```

`config.go`:

```go
package main

import (
	_ "embed"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"

	"github.com/tailscale/hujson"
)

//go:embed lib/config.template.json
var templateJSON []byte

type Config struct {
	File      string                     `json:"-"` // where the config lives: HARN_CONFIG or the XDG default
	Source    string                     `json:"-"` // the file actually read; empty for the built-in template
	Raw       []byte                     `json:"-"`
	Slots     map[string]json.RawMessage `json:"slots"`
	Providers map[string]Provider        `json:"providers"`
	Harness   map[string]Harness         `json:"harness"`
}

type Provider struct {
	Kind          string            `json:"kind"`
	Label         string            `json:"label"`
	Login         string            `json:"login"`
	KeyCommand    []string          `json:"key_command"`
	DefaultModel  string            `json:"default_model"`
	AnthropicWire *Wire             `json:"anthropic_wire"`
	OpenAIWire    *Wire             `json:"openai_wire"`
	HarnessNames  map[string]string `json:"harness_names"`
	Launcher      json.RawMessage   `json:"launcher"` // raw, so a string gets the argv-array error
}

type Wire struct {
	BaseURL string `json:"base_url"`
	KeyEnv  string `json:"key_env"`
	WireAPI string `json:"wire_api"`
}

type Harness struct {
	Wire    string   `json:"wire"`
	Binary  string   `json:"binary"`
	Account bool     `json:"account"`
	GwArgv  []string `json:"gw_argv"`
}

func (p Provider) wire(name string) *Wire {
	switch name {
	case "anthropic":
		return p.AnthropicWire
	case "openai":
		return p.OpenAIWire
	}
	return nil
}

func configPath() string {
	if p := os.Getenv("HARN_CONFIG"); p != "" {
		return p
	}
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "harn", "config.json")
}

// loadConfig reads the config, falling back to the built-in template only when no file exists.
func loadConfig() *Config {
	file := configPath()
	src := file
	raw, err := os.ReadFile(file)
	if errors.Is(err, fs.ErrNotExist) {
		src, raw = "", templateJSON
	} else if err != nil {
		die(2, "cannot read "+file, err.Error())
	}
	c, err := parseConfig(raw)
	if err != nil {
		die(2, displaySource(src)+" is not valid config", err.Error())
	}
	c.File, c.Source = file, src
	for _, name := range sortedKeys(c.Providers) {
		if name == "gw" || name == "local" || name == "account" {
			die(2, "provider name '"+name+"' is reserved", "rename providers."+name+" in "+displaySource(src))
		}
	}
	return c
}

func parseConfig(raw []byte) (*Config, error) {
	std, err := hujson.Standardize(append([]byte(nil), raw...))
	if err != nil {
		return nil, err
	}
	var c Config
	if err := json.Unmarshal(std, &c); err != nil {
		return nil, err
	}
	c.Raw = raw
	return &c, nil
}

func displaySource(src string) string {
	if src == "" {
		return "built-in template"
	}
	return src
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
```

`run.go`:

```go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/tailscale/hujson"
)

type invocation struct {
	harness, source, model string
	show                   bool
	pass                   []string
}

type envVar struct {
	name, value string
	redaction   string // printed by --show in place of value when set
}

type plan struct {
	provider string // empty for the subscription
	label    string
	kind     string
	env      []envVar
	argv     []string
}

func (p *plan) set(name, value string) { p.env = append(p.env, envVar{name: name, value: value}) }

var baseVars = []string{"ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL"}

func run(cfg *Config, args []string) {
	inv := parseArgs(args)
	h, ok := cfg.Harness[inv.harness]
	if !ok || h.Binary == "" {
		die(2, fmt.Sprintf("unknown harness '%s'", inv.harness),
			"known harnesses: "+strings.Join(sortedKeys(cfg.Harness), ", "),
			"add one under 'harness' in "+cfg.File)
	}
	p := resolveSource(cfg, inv, h)
	switch p.kind {
	case "account":
		kindAccount(inv, h, p)
	default:
		die(2, fmt.Sprintf("provider '%s' has unknown kind '%s'", p.provider, p.kind), "kind is one of: endpoint, launcher")
	}
	if h.Wire == "anthropic" && p.kind != "launcher" {
		warnClaudeSettings()
	}
	execute(cfg, inv, p)
}

func parseArgs(args []string) invocation {
	var inv invocation
	var pos []string
	for i, a := range args {
		if a == "--" {
			inv.pass = args[i+1:]
			break
		}
		switch {
		case a == "--show":
			inv.show = true
		case strings.HasPrefix(a, "-"):
			die(2, "unknown flag: "+a, "see: harn --help")
		default:
			pos = append(pos, a)
		}
	}
	if len(pos) == 0 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	if len(pos) > 3 {
		die(2, "too many arguments: "+strings.Join(pos, " "), usage)
	}
	inv.harness = pos[0]
	if len(pos) > 1 {
		inv.source = pos[1]
	}
	if len(pos) > 2 {
		inv.model = pos[2]
	}
	return inv
}

func resolveSource(cfg *Config, inv invocation, h Harness) *plan {
	p := &plan{kind: "account", label: "subscription"}
	switch inv.source {
	case "", "account":
	case "gw", "local":
		var name string
		if raw, ok := cfg.Slots[inv.source]; ok && json.Unmarshal(raw, &name) != nil {
			die(2, "slots."+inv.source+" must be a provider name", "set slots."+inv.source+" in "+cfg.File)
		}
		if name == "" {
			die(2, "slot '"+inv.source+"' has no provider", "set slots."+inv.source+" in "+cfg.File)
		}
		p.provider = name
	default:
		p.provider = inv.source
	}
	if p.provider == "" {
		if !h.Account {
			die(2, inv.harness+" has no subscription login; use gw, local or a provider")
		}
		return p
	}
	pr, ok := cfg.Providers[p.provider]
	if !ok || pr.Kind == "" {
		die(2, "unknown source '"+p.provider+"'", "known: account, gw, local, "+strings.Join(sortedKeys(cfg.Providers), ", "))
	}
	p.kind, p.label = pr.Kind, pr.Label
	if p.label == "" {
		p.label = "api"
	}
	return p
}

func kindAccount(inv invocation, h Harness, p *plan) {
	p.argv = []string{h.Binary}
	if inv.model != "" {
		p.argv = append(p.argv, "--model", inv.model)
	}
	p.argv = append(p.argv, inv.pass...)
}

// keyEnv is the variable a provider's key travels in on a wire.
func keyEnv(cfg *Config, wire, provider string) (string, error) {
	env := ""
	if w := cfg.Providers[provider].wire(wire); w != nil {
		env = w.KeyEnv
	}
	if env == "" && wire == "anthropic" {
		env = "ANTHROPIC_AUTH_TOKEN"
	}
	if env == "" {
		env = derivedKeyEnv(provider)
	}
	if !validEnvName(env) {
		return "", fmt.Errorf("'%s' is not a valid environment variable name", env)
	}
	return env, nil
}

func derivedKeyEnv(provider string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(provider) {
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	return b.String() + "_API_KEY"
}

func validEnvName(s string) bool {
	for i, r := range s {
		letter := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || r == '_'
		if !letter && (i == 0 || r < '0' || r > '9') {
			return false
		}
	}
	return s != ""
}

// cleanVars is everything a run unsets before it sets its own variables.
func cleanVars(cfg *Config) []string {
	set := map[string]bool{}
	for _, v := range baseVars {
		set[v] = true
	}
	for name, pr := range cfg.Providers {
		if pr.Kind != "endpoint" {
			continue
		}
		for _, w := range []string{"anthropic", "openai"} {
			if env, err := keyEnv(cfg, w, name); err == nil {
				set[env] = true
			}
		}
	}
	return sortedKeys(set)
}

func warnClaudeSettings() {
	files := []string{filepath.Join(os.Getenv("HOME"), ".claude", "settings.json"), ".claude/settings.json", ".claude/settings.local.json"}
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		std, err := hujson.Standardize(raw)
		if err != nil {
			continue
		}
		var s struct {
			Env map[string]json.RawMessage `json:"env"`
		}
		if json.Unmarshal(std, &s) != nil {
			continue
		}
		for _, v := range baseVars {
			if _, ok := s.Env[v]; ok {
				warn(f + " sets provider variables under env, which override this run")
				break
			}
		}
	}
}

func execute(cfg *Config, inv invocation, p *plan) {
	vars := cleanVars(cfg)
	if inv.show {
		provider := p.provider
		if provider == "" {
			provider = "account"
		}
		fmt.Printf("# source: %s (%s)\n", provider, p.label)
		fmt.Printf("unset %s\n", strings.Join(vars, " "))
		for _, e := range p.env {
			shown := shellQuote(e.value)
			if e.redaction != "" {
				shown = e.redaction
			}
			fmt.Printf("export %s=%s\n", e.name, shown)
		}
		fmt.Print("exec")
		for _, a := range p.argv {
			fmt.Print(" " + shellQuote(a))
		}
		fmt.Println()
		return
	}
	bin, err := exec.LookPath(p.argv[0])
	if err != nil {
		die(2, fmt.Sprintf("'%s' is not on PATH", p.argv[0]), "install it, or fix its binary in "+cfg.File)
	}
	err = syscall.Exec(bin, p.argv, environ(vars, p.env))
	die(3, "cannot exec "+bin, err.Error())
}

// environ is the current environment minus every cleared and set name, plus the set values.
func environ(unset []string, set []envVar) []string {
	drop := map[string]bool{}
	for _, v := range unset {
		drop[v] = true
	}
	for _, e := range set {
		drop[e.name] = true
	}
	var out []string
	for _, kv := range os.Environ() {
		if name, _, _ := strings.Cut(kv, "="); !drop[name] {
			out = append(out, kv)
		}
	}
	for _, e := range set {
		out = append(out, e.name+"="+e.value)
	}
	return out
}
```

`quote.go`:

```go
package main

import (
	"fmt"
	"strings"
)

// shellQuote quotes s the way bash's printf %q does, so a --show line pastes back as the same words.
func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 0x20 || s[i] == 0x7f {
			return ansiQuote(s)
		}
	}
	var b strings.Builder
	for _, r := range s {
		if !safeRune(r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String()
}

func safeRune(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') ||
		strings.ContainsRune("_./:=@%+,-", r) || r >= 0x80
}

// ansiQuote writes bash's $'...' form, for strings holding control characters.
func ansiQuote(s string) string {
	var b strings.Builder
	b.WriteString("$'")
	for i := 0; i < len(s); i++ {
		switch c := s[i]; c {
		case '\\':
			b.WriteString(`\\`)
		case '\'':
			b.WriteString(`\'`)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		case '\r':
			b.WriteString(`\r`)
		default:
			if c < 0x20 || c == 0x7f {
				fmt.Fprintf(&b, `\x%02x`, c)
			} else {
				b.WriteByte(c)
			}
		}
	}
	b.WriteByte('\'')
	return b.String()
}
```

Then fetch the library:

```bash
go get github.com/tailscale/hujson@latest && go mod tidy
```

- [ ] **Step 7: Run the unit tests to verify they pass**

Run: `go test ./...`
Expected: `ok  	github.com/dean-harel/harn`

- [ ] **Step 8: Run the account checks to verify they pass**

Run: `/bin/bash tests/run.sh t_account`
Expected: every line `PASS:`, ending `0 failed`.

- [ ] **Step 9: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add go.mod go.sum main.go config.go run.go quote.go quote_test.go config_test.go tests/run.sh tests/lib.sh tests/t_account.sh .gitignore
git commit -m "feat: port the subscription path and --show to Go"
```

Expected: `clean`, then the commit.

---

### Task 2: The endpoint kind with key_command credentials

**Files:**
- Create: `credential.go`
- Modify: `run.go` (the `switch p.kind` in `run`; add `kindEndpoint`), `tests/t_endpoint.sh` (append)

**Interfaces:**
- Consumes: `Config`, `Provider.wire`, `plan`, `plan.set`, `envVar`, `invocation`, `keyEnv`, `die` from Task 1.
- Produces:
  - `func credential(cfg *Config, name string, show bool) (value, redaction string)`
  - `func keyValue(cfg *Config, name string) string`
  - `func storeFile(name string) string`, `func storeRead(name string) string`

- [ ] **Step 1: Add the Review Focus check to `tests/t_endpoint.sh`**

Append:

```bash
# Review Focus 2: a key_command whose binary is missing is named, and nothing launches.
nk=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["no-such-key-command"])')
OUT=$(HARN_CONFIG="$nk" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1); RC=$?
code "missing key_command binary" "$RC" 2
has "missing key_command names the provider" "$OUT" "key_command for 'openrouter' failed"
```

- [ ] **Step 2: Run the endpoint checks to verify they fail**

Run: `/bin/bash tests/run.sh t_endpoint`
Expected: FAIL lines such as `FAIL: claude gw --show`, with output `harn: provider 'openrouter' has unknown kind 'endpoint'`.

- [ ] **Step 3: Write `credential.go`**

```go
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// credential returns the provider's key and the redaction --show prints in its place.
// With show set it never resolves the key.
func credential(cfg *Config, name string, show bool) (value, redaction string) {
	pr := cfg.Providers[name]
	hasLogin, hasCmd := pr.Login != "", len(pr.KeyCommand) > 0
	if hasLogin && hasCmd {
		die(2, fmt.Sprintf("provider '%s' sets both login and key_command", name), "keep one in "+cfg.File)
	}
	if !hasLogin && !hasCmd {
		die(2, fmt.Sprintf("provider '%s' has no credential", name),
			fmt.Sprintf("set providers.%s.login or providers.%s.key_command", name, name))
	}
	if hasLogin {
		redaction = "<redacted: login " + pr.Login + ">"
	} else {
		redaction = "<redacted: key_command " + strings.Join(pr.KeyCommand, " ") + ">"
	}
	if show {
		return "", redaction
	}
	return keyValue(cfg, name), redaction
}

func keyValue(cfg *Config, name string) string {
	pr := cfg.Providers[name]
	if len(pr.KeyCommand) == 0 {
		return storeRead(name)
	}
	cmd := exec.Command(pr.KeyCommand[0], pr.KeyCommand[1:]...)
	cmd.Stdin, cmd.Stderr = os.Stdin, os.Stderr
	out, err := cmd.Output()
	shown := "command: " + strings.Join(pr.KeyCommand, " ")
	if err != nil {
		die(2, fmt.Sprintf("key_command for '%s' failed", name), shown)
	}
	key := strings.TrimRight(string(out), "\n")
	if key == "" {
		die(2, fmt.Sprintf("key_command for '%s' printed nothing", name), shown)
	}
	return key
}

func storeFile(name string) string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(base, "harn", "keys", name)
}

func storeRead(name string) string {
	b, err := os.ReadFile(storeFile(name))
	if err != nil {
		die(2, fmt.Sprintf("no stored key for '%s'", name), "run: harn login "+name)
	}
	return string(b)
}
```

- [ ] **Step 4: Add the endpoint kind to `run.go`**

In `run`, add a case to the `switch p.kind`:

```go
	case "endpoint":
		kindEndpoint(cfg, inv, h, p)
```

Add after `kindAccount`:

```go
func kindEndpoint(cfg *Config, inv invocation, h Harness, p *plan) {
	pr := cfg.Providers[p.provider]
	w := pr.wire(h.Wire)
	if w == nil || w.BaseURL == "" {
		die(2, fmt.Sprintf("provider '%s' has no %s_wire, which %s needs", p.provider, h.Wire, inv.harness),
			fmt.Sprintf("set providers.%s.%s_wire.base_url in %s", p.provider, h.Wire, cfg.File))
	}
	model := inv.model
	if model == "" {
		model = pr.DefaultModel
	}
	if model == "" {
		die(2, fmt.Sprintf("no model given and provider '%s' has no default", p.provider),
			fmt.Sprintf("pass one: harn %s %s <model>", inv.harness, inv.source),
			fmt.Sprintf("or set providers.%s.default_model", p.provider))
	}
	env, err := keyEnv(cfg, h.Wire, p.provider)
	if err != nil {
		die(2, err.Error(), fmt.Sprintf("set providers.%s.%s_wire.key_env to a valid name", p.provider, h.Wire))
	}
	value, redaction := credential(cfg, p.provider, inv.show)
	key := envVar{name: env, value: value, redaction: redaction}
	switch h.Wire {
	case "anthropic":
		p.set("ANTHROPIC_BASE_URL", w.BaseURL)
		p.env = append(p.env, key)
		if env == "ANTHROPIC_API_KEY" {
			p.set("ANTHROPIC_AUTH_TOKEN", "")
		} else {
			p.set("ANTHROPIC_API_KEY", "")
		}
		p.argv = []string{h.Binary, "--model", model}
	case "openai":
		p.env = append(p.env, key)
		name := p.provider
		if n := pr.HarnessNames[inv.harness]; n != "" {
			name = n
		}
		wireAPI := w.WireAPI
		if wireAPI == "" {
			wireAPI = "responses"
		}
		tmpl := h.GwArgv
		if tmpl == nil {
			tmpl = []string{"--provider", "{provider}", "--model", "{model}"}
		}
		r := strings.NewReplacer("{provider}", name, "{model}", model, "{base_url}", w.BaseURL,
			"{key_env}", env, "{wire_api}", wireAPI)
		p.argv = []string{h.Binary}
		for _, t := range tmpl {
			p.argv = append(p.argv, r.Replace(t))
		}
	default:
		die(2, fmt.Sprintf("harness '%s' has unknown wire '%s'", inv.harness, h.Wire), "wire is one of: anthropic, openai")
	}
	p.argv = append(p.argv, inv.pass...)
}
```

- [ ] **Step 5: Run the checks to verify they pass**

Run: `/bin/bash tests/run.sh t_account t_endpoint`
Expected: every line `PASS:`, ending `0 failed`.

- [ ] **Step 6: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add credential.go run.go tests/t_endpoint.sh
git commit -m "feat: port the endpoint kind and key_command credentials to Go"
```

---

### Task 3: The launcher kind

**Files:**
- Modify: `run.go` (the `switch p.kind` in `run`; add `kindLauncher`)

**Interfaces:**
- Consumes: `Config`, `plan`, `invocation`, `die` from Task 1.
- Produces: `func kindLauncher(cfg *Config, inv invocation, p *plan)`.

- [ ] **Step 1: Run the launcher checks to verify they fail**

Run: `/bin/bash tests/run.sh t_launcher`
Expected: FAIL lines, with output `harn: provider 'ollama' has unknown kind 'launcher'`.

- [ ] **Step 2: Add the launcher kind to `run.go`**

In `run`, add a case to the `switch p.kind`:

```go
	case "launcher":
		kindLauncher(cfg, inv, p)
```

Add after `kindEndpoint`:

```go
func kindLauncher(cfg *Config, inv invocation, p *plan) {
	pr := cfg.Providers[p.provider]
	var argv []string
	if err := json.Unmarshal(pr.Launcher, &argv); err != nil {
		die(2, fmt.Sprintf("providers.%s.launcher must be an argv array", p.provider), `for example: ["ollama", "launch"]`)
	}
	if len(argv) == 0 {
		die(2, fmt.Sprintf("providers.%s.launcher is empty", p.provider))
	}
	p.argv = append(argv, inv.harness)
	model := inv.model
	if model == "" {
		model = pr.DefaultModel
	}
	if model != "" {
		p.argv = append(p.argv, "--model", model)
	}
	if len(inv.pass) > 0 {
		p.argv = append(append(p.argv, "--"), inv.pass...)
	}
}
```

- [ ] **Step 3: Run the checks to verify they pass**

Run: `/bin/bash tests/run.sh t_account t_endpoint t_launcher`
Expected: every line `PASS:`, ending `0 failed`.

- [ ] **Step 4: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add run.go
git commit -m "feat: port the launcher kind to Go"
```

---

### Task 4: The key store, paste login and harn key

**Files:**
- Create: `login.go`, `login_test.go`, `credential_test.go`
- Modify: `credential.go` (add `storeWrite`), `main.go` (the `switch first` in `main`), `tests/t_store.sh` (insert before `rm -f "$f"`), `go.mod`, `go.sum`

**Interfaces:**
- Consumes: `Config`, `loadConfig`, `sortedKeys`, `die` (Task 1); `keyValue`, `storeFile` (Task 2).
- Produces:
  - `func storeWrite(name, key string) (string, error)`: returns the file written
  - `func cmdLogin(cfg *Config, args []string)`, `func cmdKey(cfg *Config, args []string)`, `func requireProvider(cfg *Config, name string)`
  - `func readLine(r io.Reader) (string, error)`: one line without its newline; the rest of the line kept byte for byte
  - `func readSecretLine(f *os.File) (string, error)`: echo off when `f` is a terminal

- [ ] **Step 1: Add the Review Focus check to `tests/t_store.sh`**

Insert immediately before the line `rm -f "$f"`:

```bash
# Review Focus 3: a key file that exists with a looser mode is 0600 after a new login.
chmod 644 "$f"
printf 'sk-oc-third\n' | "$HARN" login ollama-cloud >/dev/null 2>&1
perm=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")
code "a new login tightens the mode to 0600" "$perm" 600
```

- [ ] **Step 2: Write the failing unit tests**

`credential_test.go`:

```go
package main

import (
	"os"
	"testing"
)

func TestStoreWriteIsByteExactAndPrivate(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	path, err := storeWrite("ollama-cloud", "sk-oc-pasted ")
	if err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(path)
	if string(got) != "sk-oc-pasted " {
		t.Errorf("stored %q", got)
	}
	if fi, _ := os.Stat(path); fi.Mode().Perm() != 0o600 {
		t.Errorf("mode %v", fi.Mode().Perm())
	}
}

func TestStoreWriteTightensAnExistingFile(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	path, _ := storeWrite("p", "old")
	if err := os.Chmod(path, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := storeWrite("p", "new"); err != nil {
		t.Fatal(err)
	}
	if fi, _ := os.Stat(path); fi.Mode().Perm() != 0o600 {
		t.Errorf("mode %v after a second write", fi.Mode().Perm())
	}
}
```

`login_test.go`:

```go
package main

import (
	"strings"
	"testing"
)

func TestReadLine(t *testing.T) {
	cases := map[string]string{
		"sk-oc-pasted \n": "sk-oc-pasted ",
		"no-newline":      "no-newline",
		"\n":              "",
		"":                "",
		"first\nsecond\n": "first",
	}
	for in, want := range cases {
		got, err := readLine(strings.NewReader(in))
		if err != nil || got != want {
			t.Errorf("readLine(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
}
```

Run: `go test ./...`
Expected: FAIL, `undefined: storeWrite` and `undefined: readLine`.

- [ ] **Step 3: Add `storeWrite` to `credential.go`**

```go
// storeWrite writes the key byte for byte, mode 0600 even over an existing file.
func storeWrite(name, key string) (string, error) {
	path := storeFile(name)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return path, err
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return path, err
	}
	if err := f.Chmod(0o600); err != nil {
		f.Close()
		return path, err
	}
	if _, err := f.WriteString(key); err != nil {
		f.Close()
		return path, err
	}
	return path, f.Close()
}
```

- [ ] **Step 4: Write `login.go`**

```go
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"
)

func cmdLogin(cfg *Config, args []string) {
	if len(args) == 0 || args[0] == "" {
		die(2, "usage: harn login <provider> [--no-open]")
	}
	name := args[0]
	requireProvider(cfg, name)
	switch m := cfg.Providers[name].Login; m {
	case "paste":
		loginPaste(name, args[1:])
	case "":
		die(2, fmt.Sprintf("provider '%s' has no login", name), "it uses key_command; nothing to store")
	default:
		die(2, fmt.Sprintf("provider '%s' has unknown login '%s'", name, m), "login is one of: openrouter-pkce, paste")
	}
}

func cmdKey(cfg *Config, args []string) {
	if len(args) == 0 || args[0] == "" {
		die(2, "usage: harn key <provider>")
	}
	requireProvider(cfg, args[0])
	fmt.Println(keyValue(cfg, args[0]))
}

func requireProvider(cfg *Config, name string) {
	if pr, ok := cfg.Providers[name]; !ok || pr.Kind == "" {
		die(2, fmt.Sprintf("unknown provider '%s'", name), "known: "+strings.Join(sortedKeys(cfg.Providers), ", "))
	}
}

func loginPaste(name string, args []string) {
	if len(args) > 0 {
		die(2, "unknown argument: "+args[0], "usage: harn login "+name)
	}
	fmt.Fprintf(os.Stderr, "Paste the key for %s (input hidden): ", name)
	key, err := readSecretLine(os.Stdin)
	fmt.Fprintln(os.Stderr)
	if err != nil || key == "" {
		die(2, "no key entered")
	}
	path, err := storeWrite(name, key)
	if err != nil {
		die(3, "cannot write "+path, err.Error())
	}
	fmt.Fprintf(os.Stderr, "harn: stored the key for %s in %s\n", name, path)
}

func readLine(r io.Reader) (string, error) {
	s, err := bufio.NewReader(r).ReadString('\n')
	if err != nil && err != io.EOF {
		return "", err
	}
	return strings.TrimSuffix(s, "\n"), nil
}

func readSecretLine(f *os.File) (string, error) {
	if fd := int(f.Fd()); term.IsTerminal(fd) {
		b, err := term.ReadPassword(fd)
		return string(b), err
	}
	return readLine(f)
}
```

In `main.go`, add to the `switch first` in `main`, before the closing brace:

```go
	case "login":
		cmdLogin(loadConfig(), args[1:])
		return
	case "key":
		cmdKey(loadConfig(), args[1:])
		return
```

Then fetch the library:

```bash
go get golang.org/x/term@latest && go mod tidy
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `go test ./... && /bin/bash tests/run.sh t_account t_endpoint t_launcher t_store`
Expected: `ok  	github.com/dean-harel/harn`, then every line `PASS:`, ending `0 failed`.

- [ ] **Step 6: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add credential.go credential_test.go login.go login_test.go main.go go.mod go.sum tests/t_store.sh
git commit -m "feat: port the key store, paste login and harn key to Go"
```

---

### Task 5: The OpenRouter PKCE login

**Files:**
- Create: `pkce.go`, `pkce_test.go`
- Modify: `login.go` (the `switch` in `cmdLogin`), `tests/t_pkce.sh` (whole file)

**Interfaces:**
- Consumes: `die` (Task 1); `storeWrite`, `readLine` (Task 4).
- Produces:
  - `const openRouterBase = "https://openrouter.ai"`
  - `func pkceVerifier() (string, error)`, `func pkceChallenge(verifier string) string`
  - `func authURL(challenge, label string) string`
  - `func exchangeCode(base, code, verifier string) (string, error)`
  - `type cliError struct { code int; msg string; hints []string }`: a failure the caller reports through `die`
  - `func pkceLogin(in io.Reader, out io.Writer, base, name string, open func(string)) (string, error)`: the whole flow from printed URL to stored key; returns the file written
  - `func loginPKCE(name string, args []string)`: parses `--no-open` and runs `pkceLogin` on the terminal

- [ ] **Step 1: Rewrite `tests/t_pkce.sh` for the Go binary**

The code exchange and the RFC vector move to `pkce_test.go`, so the stub `curl` and `jq` and the `--pkce-selftest` hook go. Replace the file with:

```bash
# OpenRouter PKCE login from outside; the code exchange and the PKCE math are in pkce_test.go.

rec=$(mktemp -d)
stub open "echo opened >> '$rec/opened'; exit 1"
stub xdg-open "echo opened >> '$rec/opened'; exit 1"
OUT=$(printf '\n' | PATH="$STUBS:$PATH" "$HARN" login openrouter --no-open 2>&1); RC=$?
code "an empty code is refused" "$RC" 2
has "refusal names the missing code" "$OUT" "no code entered"
has "prints the auth URL" "$OUT" "https://openrouter.ai/auth?code_challenge="
has "URL uses S256" "$OUT" "code_challenge_method=S256"
has "URL labels the key" "$OUT" "key_label=harn-"
[ -e "$rec/opened" ] && bad "--no-open opens nothing" || ok "--no-open opens nothing"

OUT=$(printf '\n' | "$HARN" login openrouter --bogus 2>&1); RC=$?
code "unknown login flag" "$RC" 2
has "unknown login flag is named" "$OUT" "unknown flag: --bogus"
```

- [ ] **Step 2: Write the failing unit tests**

`pkce_test.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestPKCEChallengeMatchesRFC7636AppendixB(t *testing.T) {
	got := pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
	if got != "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" {
		t.Errorf("challenge %s", got)
	}
}

func TestPKCEVerifierShape(t *testing.T) {
	v, err := pkceVerifier()
	if err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_-]{64}$`).MatchString(v) {
		t.Errorf("verifier %q", v)
	}
}

func TestAuthURL(t *testing.T) {
	u, err := url.Parse(authURL("chal", "harn-host"))
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if u.Scheme != "https" || u.Host != "openrouter.ai" || u.Path != "/auth" {
		t.Errorf("url %s", u)
	}
	if q.Get("code_challenge") != "chal" || q.Get("code_challenge_method") != "S256" || q.Get("key_label") != "harn-host" {
		t.Errorf("query %v", q)
	}
}

func TestExchangeCodeReturnsKey(t *testing.T) {
	var got map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/api/v1/auth/keys" {
			t.Errorf("request %s %s", r.Method, r.URL.Path)
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("content type %q", ct)
		}
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		fmt.Fprint(w, `{"key":"sk-or-from-pkce"}`)
	}))
	defer srv.Close()
	key, err := exchangeCode(srv.URL, "the-code-123", "verifier-abc")
	if err != nil || key != "sk-or-from-pkce" {
		t.Fatalf("key %q, err %v", key, err)
	}
	if got["code"] != "the-code-123" || got["code_verifier"] != "verifier-abc" || got["code_challenge_method"] != "S256" {
		t.Errorf("body %v", got)
	}
}

func TestExchangeCodeReportsTheAPIError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprint(w, `{"error":{"message":"invalid code"}}`)
	}))
	defer srv.Close()
	if _, err := exchangeCode(srv.URL, "bad", "v"); err == nil || err.Error() != "invalid code" {
		t.Errorf("err %v", err)
	}
}

func TestExchangeCodeReportsANonJSONBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprint(w, "upstream down")
	}))
	defer srv.Close()
	if _, err := exchangeCode(srv.URL, "c", "v"); err == nil || err.Error() != "upstream down" {
		t.Errorf("err %v", err)
	}
}

func TestPKCELoginStoresTheReturnedKey(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	var body map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		fmt.Fprint(w, `{"key":"sk-or-from-pkce"}`)
	}))
	defer srv.Close()
	var out bytes.Buffer
	opened := ""
	path, err := pkceLogin(strings.NewReader("the-code-123\n"), &out, srv.URL, "openrouter", func(u string) { opened = u })
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(path); string(got) != "sk-or-from-pkce" {
		t.Errorf("stored %q", got)
	}
	if body["code"] != "the-code-123" {
		t.Errorf("code %q", body["code"])
	}
	if want := "code_challenge=" + pkceChallenge(body["code_verifier"]); !strings.Contains(out.String(), want) {
		t.Errorf("the printed URL lacks the challenge for the verifier sent (%s):\n%s", want, out.String())
	}
	if opened == "" || !strings.Contains(out.String(), opened) {
		t.Error("the URL opened must be the URL printed")
	}
}

func TestPKCELoginRefusesAnEmptyCode(t *testing.T) {
	_, err := pkceLogin(strings.NewReader("\n"), io.Discard, "http://unused.invalid", "openrouter", nil)
	var ce *cliError
	if !errors.As(err, &ce) || ce.code != 2 || ce.msg != "no code entered" {
		t.Errorf("err %v", err)
	}
}
```

Run: `go test ./...`
Expected: FAIL, `undefined: pkceChallenge`, `undefined: authURL`, `undefined: exchangeCode`.

- [ ] **Step 3: Write `pkce.go`**

```go
package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

const openRouterBase = "https://openrouter.ai"

// pkceVerifier is 48 random bytes as 64 base64url characters (RFC 7636 allows 43 to 128).
func pkceVerifier() (string, error) {
	b := make([]byte, 48)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func pkceChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func authURL(challenge, label string) string {
	q := url.Values{}
	q.Set("code_challenge", challenge)
	q.Set("code_challenge_method", "S256")
	q.Set("key_label", label)
	return openRouterBase + "/auth?" + q.Encode()
}

func exchangeCode(base, code, verifier string) (string, error) {
	body, err := json.Marshal(map[string]string{"code": code, "code_verifier": verifier, "code_challenge_method": "S256"})
	if err != nil {
		return "", err
	}
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Post(base+"/api/v1/auth/keys", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", err
	}
	var r struct {
		Key   string          `json:"key"`
		Error json.RawMessage `json:"error"`
	}
	if json.Unmarshal(raw, &r) == nil && r.Key != "" {
		return r.Key, nil
	}
	return "", errors.New(apiError(raw, r.Error))
}

// apiError reads OpenRouter's error message, falling back to the raw body.
func apiError(raw []byte, e json.RawMessage) string {
	var obj struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(e, &obj) == nil && obj.Message != "" {
		return obj.Message
	}
	var s string
	if json.Unmarshal(e, &s) == nil && s != "" {
		return s
	}
	if len(e) == 0 && json.Valid(raw) {
		return "no error message"
	}
	return strings.TrimSpace(string(raw))
}

// cliError carries the exit code and hints for a failure the caller reports through die.
type cliError struct {
	code  int
	msg   string
	hints []string
}

func (e *cliError) Error() string { return e.msg }

func loginPKCE(name string, args []string) {
	open := openBrowser
	for _, a := range args {
		if a != "--no-open" {
			die(2, "unknown flag: "+a, fmt.Sprintf("usage: harn login %s [--no-open]", name))
		}
		open = nil
	}
	path, err := pkceLogin(os.Stdin, os.Stderr, openRouterBase, name, open)
	var ce *cliError
	if errors.As(err, &ce) {
		die(ce.code, ce.msg, ce.hints...)
	}
	fmt.Fprintf(os.Stderr, "harn: stored the key for %s in %s\n", name, path)
}

// pkceLogin prints the URL, reads the code from in, exchanges it at base and stores the key.
func pkceLogin(in io.Reader, out io.Writer, base, name string, open func(string)) (string, error) {
	verifier, err := pkceVerifier()
	if err != nil {
		return "", &cliError{3, "cannot generate a PKCE verifier", []string{err.Error()}}
	}
	u := authURL(pkceChallenge(verifier), "harn-"+shortHostname())
	fmt.Fprintf(out, "Open this URL, approve, then paste the code it shows:\n  %s\n", u)
	if open != nil {
		open(u)
	}
	fmt.Fprint(out, "Code: ")
	code, _ := readLine(in)
	if code = strings.TrimSpace(code); code == "" {
		return "", &cliError{2, "no code entered", nil}
	}
	key, err := exchangeCode(base, code, verifier)
	if err != nil {
		return "", &cliError{2, "OpenRouter returned no key", []string{err.Error()}}
	}
	path, err := storeWrite(name, key)
	if err != nil {
		return "", &cliError{3, "cannot write " + path, []string{err.Error()}}
	}
	return path, nil
}

func shortHostname() string {
	h, err := os.Hostname()
	if err != nil || h == "" {
		return "unknown"
	}
	h, _, _ = strings.Cut(h, ".")
	return h
}

func openBrowser(u string) {
	cmd := "xdg-open"
	if runtime.GOOS == "darwin" {
		cmd = "open"
	}
	if path, err := exec.LookPath(cmd); err == nil {
		_ = exec.Command(path, u).Run()
	}
}
```

In `login.go`, add to the `switch` in `cmdLogin`, after the `paste` case:

```go
	case "openrouter-pkce":
		loginPKCE(name, args[1:])
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go test ./... && /bin/bash tests/run.sh t_account t_endpoint t_launcher t_store t_pkce`
Expected: `ok  	github.com/dean-harel/harn`, then every line `PASS:`, ending `0 failed`.

- [ ] **Step 5: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add pkce.go pkce_test.go login.go tests/t_pkce.sh
git commit -m "feat: port the OpenRouter PKCE login to Go"
```

---

### Task 6: Config subcommands

**Files:**
- Create: `configcmd.go`
- Modify: `main.go` (the `switch first` in `main`), `tests/t_config.sh` (append)

**Interfaces:**
- Consumes: `configPath`, `loadConfig`, `templateJSON`, `Config.Raw`, `die` (Task 1).
- Produces: `func cmdConfig(args []string)`.

- [ ] **Step 1: Add the Review Focus checks to `tests/t_config.sh`**

Append:

```bash
# Review Focus 5: comments and trailing commas parse; invalid JSON is a config error naming the file.
cm=$(mktemp)
cat > "$cm" <<'EOF'
{
  // the everyday account
  "harness": { "claude": { "wire": "anthropic", "binary": "claude", "account": true, }, },
}
EOF
OUT=$(HARN_CONFIG="$cm" "$HARN" claude --show 2>&1); RC=$?
code "config with comments and trailing commas" "$RC" 0
OUT=$(HARN_CONFIG="$cm" "$HARN" config 2>&1)
has "config prints the file as written" "$OUT" "// the everyday account"
iv=$(mktemp); printf '{"slots": ' > "$iv"
OUT=$(HARN_CONFIG="$iv" "$HARN" claude --show 2>&1); RC=$?
code "invalid config" "$RC" 2
has "invalid config names the file" "$OUT" "$iv is not valid config"
```

- [ ] **Step 2: Run the config checks to verify they fail**

Run: `/bin/bash tests/run.sh t_config`
Expected: FAIL lines such as `FAIL: config prints`, with output `harn: unknown harness 'config'`.

- [ ] **Step 3: Write `configcmd.go`**

```go
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

func cmdConfig(args []string) {
	sub := ""
	if len(args) > 0 {
		sub = args[0]
	}
	path := configPath()
	switch sub {
	case "":
		c := loadConfig()
		os.Stdout.Write(c.Raw)
		if n := len(c.Raw); n == 0 || c.Raw[n-1] != '\n' {
			fmt.Println()
		}
	case "edit":
		editor := strings.Fields(os.Getenv("EDITOR"))
		if len(editor) == 0 {
			editor = []string{"vi"}
		}
		bin, err := exec.LookPath(editor[0])
		if err != nil {
			die(2, fmt.Sprintf("'%s' is not on PATH", editor[0]), "set EDITOR to your editor")
		}
		err = syscall.Exec(bin, append(editor, path), os.Environ())
		die(3, "cannot exec "+bin, err.Error())
	case "init":
		force := len(args) > 1 && args[1] == "--force"
		if _, err := os.Stat(path); err == nil && !force {
			die(2, path+" already exists", "pass --force to overwrite it")
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			die(2, "cannot write "+path, err.Error())
		}
		if err := os.WriteFile(path, templateJSON, 0o644); err != nil {
			die(2, "cannot write "+path, err.Error())
		}
		fmt.Printf("wrote %s\n", path)
	default:
		die(2, fmt.Sprintf("unknown config subcommand '%s'", sub), "use: harn config [init [--force] | edit]")
	}
}
```

In `main.go`, add to the `switch first` in `main`, before the `login` case:

```go
	case "config":
		cmdConfig(args[1:])
		return
```

- [ ] **Step 4: Run the whole suite to verify it passes**

Run: `go test ./... && /bin/bash tests/run.sh`
Expected: `ok  	github.com/dean-harel/harn`, then every line `PASS:`, ending `0 failed`.

- [ ] **Step 5: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add configcmd.go main.go tests/t_config.sh
git commit -m "feat: port the config subcommands to Go"
```

---

### Task 7: Cut over from bash to Go

**Files:**
- Delete: `bin/harn`
- Modify: `tests/t_config.sh` (the release checks at the end of the original file), `release-please-config.json`, `Formula/harn.rb` (whole file), `.github/workflows/ci.yml` (whole file), `README.md` (Install and Develop sections, Config intro), `AGENTS.md` (whole file), `CONTRIBUTING.md` (whole file), `tests/lib.sh:1`

**Interfaces:**
- Consumes: the whole Go binary from Tasks 1 to 6.
- Produces: a repository with no bash implementation; release-please rewrites the version in `main.go` and `Formula/harn.rb`.

- [ ] **Step 1: Replace the release checks in `tests/t_config.sh`**

Replace the block from `jq -e '.packages["."] | .["release-type"] == "simple"` through the line ending `bad "README names openssl for minimal Linux"` with:

```bash
jq -e '.packages["."] | .["release-type"] == "simple" and .["bump-minor-pre-major"] == true
  and (.["extra-files"] | index("main.go") and index("Formula/harn.rb"))' \
  "$ROOT/release-please-config.json" >/dev/null 2>&1 && ok "release-please config" || bad "release-please config"
grep -q 'x-release-please-version' "$ROOT/main.go" && ok "version marker in main.go" || bad "version marker in main.go"
grep -q 'tag: "v[0-9.]*" # x-release-please-version' "$ROOT/Formula/harn.rb" 2>/dev/null \
  && ok "version marker in the formula" || bad "version marker in the formula"
grep -q 'depends_on "go" => :build' "$ROOT/Formula/harn.rb" && ok "formula builds with Go" || bad "formula builds with Go"
[ ! -e "$ROOT/bin/harn" ] && ok "the bash script is gone" || bad "the bash script is gone"
grep -qF 'go install github.com/dean-harel/harn@' "$ROOT/README.md" && ok "README names go install" || bad "README names go install"
```

- [ ] **Step 2: Run the config checks to verify they fail**

Run: `/bin/bash tests/run.sh t_config`
Expected: `FAIL: release-please config`, `FAIL: formula builds with Go`, `FAIL: the bash script is gone` and `FAIL: README names go install`. `version marker in main.go` already passes, since the marker exists from Task 1.

- [ ] **Step 3: Remove the bash script and point releases at Go**

```bash
git rm bin/harn
```

In `release-please-config.json`, change the `extra-files` line to:

```json
      "extra-files": ["main.go", "Formula/harn.rb"]
```

Replace `Formula/harn.rb` with:

```ruby
class Harn < Formula
  desc "One command for any AI coding harness: subscription, gateway or local model"
  homepage "https://github.com/dean-harel/harn"
  url "https://github.com/dean-harel/harn.git",
      tag: "v0.1.0" # x-release-please-version
  license "MIT"
  head "https://github.com/dean-harel/harn.git", branch: "main"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-s -w")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/harn --version")
    assert_match "usage: harn", shell_output("#{bin}/harn --help")
  end
end
```

Replace `.github/workflows/ci.yml` with:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
        with:
          go-version-file: go.mod
      - name: Vet and format
        run: |
          go vet ./...
          test -z "$(gofmt -l .)"
      - run: go test ./...
      - name: Black-box suite under the platform's /bin/bash
        run: /bin/bash tests/run.sh

  shellcheck:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: shellcheck --shell=bash tests/*.sh
```

In `tests/lib.sh`, replace line 1 with:

```bash
# Sourced by tests/run.sh. Every test runs the harn binary as a child process against an isolated HOME.
```

- [ ] **Step 4: Update the docs**

In `README.md`, replace the whole `## Install` section (from `## Install` up to the line before `## Use`) with:

````markdown
## Install

With Homebrew, on macOS or Linux:

```bash
brew tap dean-harel/harn https://github.com/dean-harel/harn
brew install dean-harel/harn/harn
```

With Go:

```bash
go install github.com/dean-harel/harn@vX.Y.Z
```

harn is one self-contained binary with no runtime dependencies.
````

In `README.md`, replace the first paragraph of `## Config` (the sentence starting "One file, `$HARN_CONFIG`") with:

```markdown
One file, `$HARN_CONFIG` or `${XDG_CONFIG_HOME:-~/.config}/harn/config.json`, in JSON with
comments and trailing commas allowed. `harn config init` writes the shipped template,
[`lib/config.template.json`](lib/config.template.json), and `harn config` prints the file as
written.
```

In `README.md`, replace the whole `## Develop` section with:

````markdown
## Develop

```bash
/bin/bash tests/run.sh          # builds .build/harn, then the black-box suite; needs Go and jq
go test ./...                   # unit tests
go run . claude gw --show
```

The suite runs under macOS `/bin/bash` 3.2 and on Linux, never launches a harness and never
reaches the network. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
````

Replace `AGENTS.md` with:

```markdown
# harn

A single Go binary that runs an AI coding harness against a subscription, a gateway API or a
local model. The standard library plus `tailscale/hujson` and `golang.org/x/term`.

## Run and test

    /bin/bash tests/run.sh              # builds .build/harn, then the black-box suite; needs Go and jq
    /bin/bash tests/run.sh t_endpoint   # one test file
    go test ./...                       # unit tests: quoting, config parsing, PKCE, the key store
    go vet ./... && gofmt -l .          # CI fails on any output from gofmt -l

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
configcmd.go is harn config. Formula/harn.rb makes the repository its own Homebrew tap and builds
from the release tag. Specs and plans are in .agents/.

## Conventions

Conventional Commits; release-please cuts releases from main. Its release PR is opened by GITHUB_TOKEN,
which starts no workflows, so that PR carries no CI; main requires no checks, so it still merges.
Requiring checks on main first needs a GitHub App token for release-please. No attribution lines anywhere.
```

Replace `CONTRIBUTING.md` with:

```markdown
# Contributing

harn's core is small on purpose: resolve a source, build an environment and an argv, exec. A new
harness or provider is a config entry, not a code change. Changes that grow the core need an
issue first.

Before a pull request: `/bin/bash tests/run.sh` and `go test ./...` pass, `go vet ./...` and
`shellcheck --shell=bash tests/*.sh` are clean, `gofmt -l .` prints nothing, and the title is a
Conventional Commit. Do not edit CHANGELOG.md; release-please writes it. You must understand every
line you submit, including any an agent wrote.
```

- [ ] **Step 5: Verify the whole cutover**

Run:

```bash
gofmt -w . && go vet ./... && go test ./... && /bin/bash tests/run.sh
docker run --rm -v "$PWD":/src -w /src koalaman/shellcheck:stable --shell=bash tests/*.sh && echo shellcheck-clean
ruby -c Formula/harn.rb
! LC_ALL=C grep -n '[^[:print:][:space:]]' README.md AGENTS.md CONTRIBUTING.md && echo ascii-clean
```

Expected: `ok  	github.com/dean-harel/harn`; every suite line `PASS:`, ending `0 failed`; `shellcheck-clean`; `Syntax OK`; `ascii-clean`.

Then run the suite on Linux as well:

```bash
docker run --rm -v "$PWD":/src -w /src golang:1 bash -c 'apt-get update -qq && apt-get install -y -qq jq >/dev/null && /bin/bash tests/run.sh' | tail -3
```

Expected: ends with `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add -A bin tests/t_config.sh tests/lib.sh release-please-config.json Formula/harn.rb .github/workflows/ci.yml README.md AGENTS.md CONTRIBUTING.md
git commit -m "refactor: replace the bash script with the Go binary"
```

---

### Task 8: The config file and the retention declaration in --show

**Files:**
- Modify: `config.go` (`Provider`), `run.go` (`plan`, `resolveSource`, `execute`), `quote.go` (add `commentText`), `quote_test.go` (append), `tests/t_account.sh` (append), `tests/t_endpoint.sh` (append), `tests/t_launcher.sh` (append), `README.md` (Config section)

**Interfaces:**
- Consumes: `Config.Source`, `displaySource`, `plan`, `execute`, `resolveSource` (Task 1).
- Produces:
  - `Provider.Retention string` (`json:"retention"`), `plan.retention string`
  - `func commentText(s string) string`: control characters become spaces
  - `--show` output begins `# config: <file or built-in template>`, then `# source: ...`, then, for an endpoint only, `# retention: <text or not declared>`.

- [ ] **Step 1: Write the failing checks**

Append to `tests/t_account.sh`:

```bash
# The config file in use heads --show.
run claude --show
first=$(printf '%s\n' "$OUT" | head -n 1)
code "first --show line names the config" "$first" "# config: $HARN_CONFIG"
OUT=$(HARN_CONFIG="$HOME/no-such-dir/config.json" "$HARN" claude --show 2>&1)
has "a missing file shows the built-in template" "$OUT" "# config: built-in template"
lacks "an account run declares no retention" "$OUT" "# retention:"
```

Append to `tests/t_endpoint.sh`:

```bash
# The retention declaration.
OUT=$(HARN_CONFIG="$kc" "$HARN" claude gw --show 2>&1)
has "undeclared retention" "$OUT" "# retention: not declared"
rt=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["true"] | .retention = "zero, by the workspace guardrail")')
OUT=$(HARN_CONFIG="$rt" "$HARN" claude gw --show 2>&1)
has "declared retention" "$OUT" "# retention: zero, by the workspace guardrail"

# Review Focus 4: a newline in config text cannot become its own line in --show.
nl=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["true"] | .retention = "zero\necho pwned" | .label = "api\necho pwned")')
OUT=$(HARN_CONFIG="$nl" "$HARN" claude gw --show 2>&1)
printf '%s\n' "$OUT" | grep -q '^echo pwned' && bad "newlines stay inside comment lines" "$OUT" || ok "newlines stay inside comment lines"
```

Append to `tests/t_launcher.sh`:

```bash
run claude local m --show
lacks "a launcher run declares no retention" "$OUT" "# retention:"
```

Append to `quote_test.go`:

```go
func TestCommentTextKeepsOneLine(t *testing.T) {
	if got := commentText("zero\necho pwned\r\t!"); got != "zero echo pwned  !" {
		t.Errorf("commentText = %q", got)
	}
}
```

- [ ] **Step 2: Run the checks to verify they fail**

Run: `go test ./... ; /bin/bash tests/run.sh t_account t_endpoint t_launcher`
Expected: `undefined: commentText`; then `FAIL: first --show line names the config`, `FAIL: undeclared retention`, `FAIL: declared retention`, `FAIL: newlines stay inside comment lines`.

- [ ] **Step 3: Implement**

In `config.go`, add to `Provider` after `DefaultModel`:

```go
	Retention     string            `json:"retention"`
```

In `quote.go`, add:

```go
// commentText keeps a value on one line, so a --show comment line stays a comment when pasted.
func commentText(s string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, s)
}
```

In `run.go`, add to `plan` after `kind string`:

```go
	retention string // the operator's declaration, for an endpoint
```

In `resolveSource`, replace `p.kind, p.label = pr.Kind, pr.Label` with:

```go
	p.kind, p.label, p.retention = pr.Kind, pr.Label, pr.Retention
```

In `execute`, replace the lines from `fmt.Printf("# source: %s (%s)\n", provider, p.label)` through the `export` loop with:

```go
		fmt.Printf("# config: %s\n", commentText(displaySource(cfg.Source)))
		fmt.Printf("# source: %s (%s)\n", commentText(provider), commentText(p.label))
		if p.kind == "endpoint" {
			r := p.retention
			if r == "" {
				r = "not declared"
			}
			fmt.Printf("# retention: %s\n", commentText(r))
		}
		fmt.Printf("unset %s\n", strings.Join(vars, " "))
		for _, e := range p.env {
			shown := shellQuote(e.value)
			if e.redaction != "" {
				shown = commentText(e.redaction)
			}
			fmt.Printf("export %s=%s\n", e.name, shown)
		}
```

In `README.md`, add at the end of the `## Config` section, after the `harness_names` paragraph:

````markdown
**Accounts.** A second account, such as a personal one beside a team one, is a second config
file. Point `HARN_CONFIG` at it, for example through an alias:

```bash
alias harnp='HARN_CONFIG=~/.config/harn/personal.json harn'
```

`--show` names the config file on its first line, so a run always shows which account it used.
Keys from `harn login` are stored by provider name, so when two files both log in to one
provider, give it a different name in each.

**Retention.** An optional `retention` string on an endpoint records what you declare about the
provider's data retention, such as `"zero, by the workspace guardrail"`. `--show` prints it, and
harn enforces nothing from it.
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go test ./... && /bin/bash tests/run.sh`
Expected: `ok  	github.com/dean-harel/harn`, then every line `PASS:`, ending `0 failed`.

- [ ] **Step 5: Vet, format and commit**

```bash
gofmt -w . && go vet ./... && echo clean
git add config.go run.go quote.go quote_test.go tests/t_account.sh tests/t_endpoint.sh tests/t_launcher.sh README.md
git commit -m "feat: show the config file and the retention declaration in --show"
```

---

### Task 9: Login options and the OpenRouter workspace pin

**Files:**
- Modify: `config.go` (`Provider.Login` type; add `LoginSpec`, `loginOptions`, `validateLogins`; call it in `loadConfig`), `config_test.go` (append), `credential.go` (`credential`), `login.go` (`cmdLogin`), `pkce.go` (`authURL`, `pkceLogin`, `loginPKCE`), `pkce_test.go` (`TestAuthURL`, the `pkceLogin` calls, append), `tests/t_endpoint.sh` (append), `tests/t_pkce.sh` (append), `README.md` (Credentials)

**Interfaces:**
- Consumes: `Provider`, `loadConfig`, `sortedKeys`, `die` (Task 1); `credential` (Task 2); `cmdLogin` (Task 4); `authURL`, `pkceLogin`, `loginPKCE` (Task 5).
- Produces:
  - `type LoginSpec struct { Method, Workspace string; Options map[string]json.RawMessage }` with `UnmarshalJSON` accepting a string or an object; `Provider.Login LoginSpec`
  - `var loginOptions = map[string][]string{"paste": nil, "openrouter-pkce": {"workspace"}}`
  - `func validateLogins(c *Config)`
  - `func authURL(challenge, label, workspace string) string`
  - `func pkceLogin(in io.Reader, out io.Writer, base, name, workspace string, open func(string)) (string, error)`, `func loginPKCE(name string, args []string, workspace string)`

- [ ] **Step 1: Write the failing checks**

Append to `tests/t_endpoint.sh`:

```bash
# Login options.
ob=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce"}')
OUT=$(HARN_CONFIG="$ob" "$HARN" claude gw --show 2>&1)
has "object login without options" "$OUT" "<redacted: login openrouter-pkce>"
ws=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": "ws-uuid-1"}')
OUT=$(HARN_CONFIG="$ws" "$HARN" claude gw --show 2>&1)
has "the redaction shows the workspace" "$OUT" "<redacted: login openrouter-pkce, workspace ws-uuid-1>"
pw=$(cfgwith '.providers["ollama-cloud"].login = {"method": "paste", "workspace": "x"}')
OUT=$(HARN_CONFIG="$pw" "$HARN" claude --show 2>&1); RC=$?
code "workspace on paste is a config error" "$RC" 2
has "workspace on paste names the field" "$OUT" "providers.ollama-cloud.login.workspace"
uo=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "team": "x"}')
OUT=$(HARN_CONFIG="$uo" "$HARN" claude --show 2>&1); RC=$?
code "unknown login option" "$RC" 2
has "unknown login option names the field" "$OUT" "providers.openrouter.login.team"
nm=$(cfgwith '.providers.openrouter.login = {"workspace": "x"}')
OUT=$(HARN_CONFIG="$nm" "$HARN" claude --show 2>&1); RC=$?
code "login object without a method" "$RC" 2
has "missing method names the field" "$OUT" "providers.openrouter.login.method"
ew=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": ""}')
OUT=$(HARN_CONFIG="$ew" "$HARN" claude --show 2>&1); RC=$?
code "empty workspace" "$RC" 2
has "empty workspace names the field" "$OUT" "providers.openrouter.login.workspace"
um=$(cfgwith '.providers.openrouter.login = "sso"')
OUT=$(HARN_CONFIG="$um" "$HARN" claude --show 2>&1); RC=$?
code "unknown login method fails at load" "$RC" 2
has "unknown login method is named" "$OUT" "unknown login 'sso'"
```

Append to `tests/t_pkce.sh`:

```bash
# The workspace pin reaches the authorization URL.
ws=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": "ws-uuid-1"}')
OUT=$(printf '\n' | HARN_CONFIG="$ws" "$HARN" login openrouter --no-open 2>&1)
has "URL pins the workspace" "$OUT" "required_workspace_id=ws-uuid-1"
OUT=$(printf '\n' | "$HARN" login openrouter --no-open 2>&1)
lacks "no pin without a workspace" "$OUT" "required_workspace_id"
```

In `pkce_test.go`, change the first line of `TestAuthURL` to `u, err := url.Parse(authURL("chal", "harn-host", ""))`, add at its end:

```go
	if _, ok := q["required_workspace_id"]; ok {
		t.Error("no workspace pin without a workspace")
	}
```

and append:

```go
func TestAuthURLPinsTheWorkspace(t *testing.T) {
	u, _ := url.Parse(authURL("chal", "harn-host", "ws-uuid-1"))
	if got := u.Query().Get("required_workspace_id"); got != "ws-uuid-1" {
		t.Errorf("required_workspace_id %q", got)
	}
}
```

Append to `config_test.go`:

```go
func TestLoginSpecAcceptsStringAndObject(t *testing.T) {
	c, err := parseConfig([]byte(`{"providers": {
  "a": {"login": "paste"},
  "b": {"login": {"method": "openrouter-pkce", "workspace": "ws-1", "team": "x"}}}}`))
	if err != nil {
		t.Fatal(err)
	}
	if c.Providers["a"].Login.Method != "paste" {
		t.Errorf("string form: %+v", c.Providers["a"].Login)
	}
	b := c.Providers["b"].Login
	if b.Method != "openrouter-pkce" || b.Workspace != "ws-1" {
		t.Errorf("object form: %+v", b)
	}
	if _, ok := b.Options["team"]; !ok {
		t.Error("an unknown option must be kept for validation")
	}
}

func TestLoginSpecRejectsANonStringWorkspace(t *testing.T) {
	if _, err := parseConfig([]byte(`{"providers": {"b": {"login": {"method": "openrouter-pkce", "workspace": 7}}}}`)); err == nil {
		t.Error("want an error for a numeric workspace")
	}
}
```

- [ ] **Step 2: Run the checks to verify they fail**

Run: `go test ./... ; /bin/bash tests/run.sh t_endpoint t_pkce`
Expected: `go test` fails to compile (`too many arguments in call to authURL`, `c.Providers["a"].Login.Method undefined`); the suite shows `FAIL: object login without options` and the other new checks.

- [ ] **Step 3: Implement**

In `config.go`, change the `Login` field of `Provider` to:

```go
	Login         LoginSpec         `json:"login"`
```

Add `"fmt"` and `"slices"` to its imports, and add after `Harness`:

```go
// LoginSpec is a login method plus the options that scope the key it creates.
// The string form "paste" is the method with no options.
type LoginSpec struct {
	Method    string
	Workspace string
	Options   map[string]json.RawMessage // every key except method, kept for validation
}

func (l *LoginSpec) UnmarshalJSON(b []byte) error {
	var s string
	if json.Unmarshal(b, &s) == nil {
		l.Method = s
		return nil
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(b, &m); err != nil {
		return fmt.Errorf("login must be a method name or an object")
	}
	if raw, ok := m["method"]; ok {
		if err := json.Unmarshal(raw, &l.Method); err != nil {
			return fmt.Errorf("login.method must be a string")
		}
	}
	delete(m, "method")
	if raw, ok := m["workspace"]; ok {
		if err := json.Unmarshal(raw, &l.Workspace); err != nil {
			return fmt.Errorf("login.workspace must be a string")
		}
	}
	l.Options = m
	return nil
}

// loginOptions lists each login method and the options it accepts.
var loginOptions = map[string][]string{"paste": nil, "openrouter-pkce": {"workspace"}}

func validateLogins(c *Config) {
	for _, name := range sortedKeys(c.Providers) {
		l := c.Providers[name].Login
		if l.Method == "" && len(l.Options) == 0 {
			continue
		}
		field := "providers." + name + ".login"
		if l.Method == "" {
			die(2, field+".method is missing", `for example: {"method": "openrouter-pkce"}`)
		}
		allowed, known := loginOptions[l.Method]
		if !known {
			die(2, fmt.Sprintf("provider '%s' has unknown login '%s'", name, l.Method), "login is one of: openrouter-pkce, paste")
		}
		for _, opt := range sortedKeys(l.Options) {
			if !slices.Contains(allowed, opt) {
				hint := fmt.Sprintf("the %s login takes no options", l.Method)
				if len(allowed) > 0 {
					hint = fmt.Sprintf("the %s login takes: %s", l.Method, strings.Join(allowed, ", "))
				}
				die(2, fmt.Sprintf("%s.%s is not an option of the %s login", field, opt, l.Method), hint)
			}
		}
		if _, ok := l.Options["workspace"]; ok && l.Workspace == "" {
			die(2, field+".workspace must be a workspace id")
		}
	}
}
```

Add `"strings"` to `config.go`'s imports as well. In `loadConfig`, add before `return c`:

```go
	validateLogins(c)
```

In `credential.go`, in `credential`, replace `pr.Login != ""` with `pr.Login.Method != ""`, and replace `redaction = "<redacted: login " + pr.Login + ">"` with:

```go
		redaction = "<redacted: login " + pr.Login.Method
		if pr.Login.Workspace != "" {
			redaction += ", workspace " + pr.Login.Workspace
		}
		redaction += ">"
```

In `login.go`, in `cmdLogin`, replace `switch m := cfg.Providers[name].Login; m {` with `switch m := cfg.Providers[name].Login.Method; m {`, and the `openrouter-pkce` case body with:

```go
		loginPKCE(name, args[1:], cfg.Providers[name].Login.Workspace)
```

In `pkce.go`, replace `authURL` with:

```go
func authURL(challenge, label, workspace string) string {
	q := url.Values{}
	q.Set("code_challenge", challenge)
	q.Set("code_challenge_method", "S256")
	q.Set("key_label", label)
	if workspace != "" {
		q.Set("required_workspace_id", workspace)
	}
	return openRouterBase + "/auth?" + q.Encode()
}
```

change `loginPKCE`'s signature to `func loginPKCE(name string, args []string, workspace string)` and its call to `pkceLogin(os.Stdin, os.Stderr, openRouterBase, name, workspace, open)`. Change `pkceLogin`'s signature to `func pkceLogin(in io.Reader, out io.Writer, base, name, workspace string, open func(string)) (string, error)` and its call to `authURL(pkceChallenge(verifier), "harn-"+shortHostname(), workspace)`. In `pkce_test.go`, add `""` as the workspace argument to both `pkceLogin` calls, before the `open` argument.

In `README.md`, replace the `"login": "openrouter-pkce"` bullet under **Credentials** with:

```markdown
- `"login": "openrouter-pkce"`: `harn login openrouter` runs OpenRouter's browser login and
  stores the key it returns. No key ever passes through your clipboard. A member of several
  OpenRouter workspaces pins the one the key is created in:
  `"login": {"method": "openrouter-pkce", "workspace": "<workspace id>"}`. OpenRouter then locks
  its workspace picker to that workspace.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go test ./... && /bin/bash tests/run.sh`
Expected: `ok  	github.com/dean-harel/harn`, then every line `PASS:`, ending `0 failed`.

- [ ] **Step 5: Vet, format, check the docs and commit**

```bash
gofmt -w . && go vet ./... && echo clean
! LC_ALL=C grep -n '[^[:print:][:space:]]' README.md && echo ascii-clean
git add config.go config_test.go credential.go login.go pkce.go pkce_test.go tests/t_endpoint.sh tests/t_pkce.sh README.md
git commit -m "feat: add login options and the OpenRouter workspace pin"
```

Expected: `clean`, `ascii-clean`, then the commit.
