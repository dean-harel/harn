package main

import (
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"

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
	Login         LoginSpec         `json:"login"`
	KeyCommand    []string          `json:"key_command"`
	DefaultModel  string            `json:"default_model"`
	Retention     string            `json:"retention"`
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
	validateLogins(c)
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
