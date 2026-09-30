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

func TestStoreReadDropsTrailingNewlines(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	path, _ := storeWrite("p", "sk-hand-written \n")
	if got := storeRead("p"); got != "sk-hand-written " {
		t.Errorf("storeRead from %s = %q", path, got)
	}
}
