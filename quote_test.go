package main

import (
	"os/exec"
	"testing"
)

func TestShellQuoteRoundTripsThroughBash(t *testing.T) {
	cases := []string{"", "plain", "hello world", "it's", `back\slash`, "a\nb", "tab\there",
		"$HOME", "`id`", "semi;colon", "~user", "glob*?[x]", "café ✓",
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
		"":                          "''",
		"hello world":               `hello\ world`,
		"it's":                      `it\'s`,
		"https://openrouter.ai/api": "https://openrouter.ai/api",
		"model_providers.x.base_url=https://h/v1": "model_providers.x.base_url=https://h/v1",
	}
	for in, w := range want {
		if got := shellQuote(in); got != w {
			t.Errorf("shellQuote(%q) = %s, want %s", in, got, w)
		}
	}
}
