package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

func cmdConfig(args []string) {
	sub := ""
	if len(args) > 0 {
		sub = args[0]
	}
	path := configPath()
	switch sub {
	case "":
		c := loadConfig()
		os.Stdout.Write(c.Raw)
		if n := len(c.Raw); n == 0 || c.Raw[n-1] != '\n' {
			fmt.Println()
		}
	case "edit":
		editor := strings.Fields(os.Getenv("EDITOR"))
		if len(editor) == 0 {
			editor = []string{"vi"}
		}
		bin, err := exec.LookPath(editor[0])
		if err != nil {
			die(2, fmt.Sprintf("'%s' is not on PATH", editor[0]), "set EDITOR to your editor")
		}
		err = syscall.Exec(bin, append(editor, path), os.Environ())
		die(3, "cannot exec "+bin, err.Error())
	case "init":
		force := len(args) > 1 && args[1] == "--force"
		if _, err := os.Stat(path); err == nil && !force {
			die(2, path+" already exists", "pass --force to overwrite it")
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			die(2, "cannot write "+path, err.Error())
		}
		if err := os.WriteFile(path, templateJSON, 0o644); err != nil {
			die(2, "cannot write "+path, err.Error())
		}
		fmt.Printf("wrote %s\n", path)
	default:
		die(2, fmt.Sprintf("unknown config subcommand '%s'", sub), "use: harn config [init [--force] | edit]")
	}
}
