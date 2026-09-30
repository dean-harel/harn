// Command harn runs an AI coding harness against a subscription, a gateway or a local model.
package main

import (
	"fmt"
	"os"
)

const version = "0.0.0-dev"

const usage = "usage: harn <harness> [<source>] [<model>] [--show] [-- <args>...]"

const helpText = `usage: harn <harness> [<source>] [<model>] [--show] [-- <args>...]

Sources:
  (none) or account     the harness's own subscription login
  gw, local             whatever that slot points at in the config
  <provider>            a named provider, for a one-off

Commands:
  harn login <provider> [--no-open]
  harn key <provider>          print the provider's key, for reuse by another command
  harn config                  print the config file
  harn config init [--force]   write the template config
  harn config edit             open the config in $EDITOR
  harn --version

Examples:
  harn claude
  harn claude gw
  harn codex gw openai/gpt-6-sol
  harn claude local qwen3-coder -- -p "hello"
  harn claude ollama-cloud --show
`

func main() {
	args := os.Args[1:]
	first := ""
	if len(args) > 0 {
		first = args[0]
	}
	switch first {
	case "--version":
		fmt.Printf("harn %s\n", version)
		return
	case "--help", "-h", "help":
		fmt.Print(helpText)
		return
	case "config":
		cmdConfig(args[1:])
		return
	case "login":
		cmdLogin(loadConfig(), args[1:])
		return
	case "key":
		cmdKey(loadConfig(), args[1:])
		return
	}
	run(loadConfig(), args)
}

func die(code int, msg string, hints ...string) {
	fmt.Fprintf(os.Stderr, "harn: %s\n", msg)
	for _, h := range hints {
		fmt.Fprintf(os.Stderr, "    %s\n", h)
	}
	os.Exit(code)
}

func warn(msg string) { fmt.Fprintf(os.Stderr, "harn: warning: %s\n", msg) }
