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
