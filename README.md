# agent

Unified launcher for AI coding harnesses.

```bash
agent claude              # account mode (default)
agent claude gw model     # via gateway
agent claude local qwen   # local model
```

## Install

Clone this repo wherever you keep tools, then source the launcher from `~/.zshrc`:

```bash
git clone git@github.com:dean-harel/agent.git /path/to/agent
echo 'source /path/to/agent/lib/agent.zsh' >> ~/.zshrc
```

## Config

```bash
agent config init    # create ~/.config/agent/config.json from template
agent config edit    # edit config
```

## Paths

- **Config:** `~/.config/agent/config.json` (or `$XDG_CONFIG_HOME/agent/config.json`)
- **Template:** ships with the repo at `lib/config.template.json`
- **Override config path:** set `AGENT_CONFIG=/path/to/config.json` (used by tests)

Requires `jq` and optionally `op` (1Password CLI) or `security` (macOS).
