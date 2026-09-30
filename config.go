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
