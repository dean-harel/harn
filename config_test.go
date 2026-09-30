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
