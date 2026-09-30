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
