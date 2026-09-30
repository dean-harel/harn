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
