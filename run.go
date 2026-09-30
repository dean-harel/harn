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
