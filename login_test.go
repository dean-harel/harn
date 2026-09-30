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
