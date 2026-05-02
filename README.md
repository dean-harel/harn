# agent

Unified launcher for AI coding harnesses.

```bash
agent claude              # account mode (default)
agent claude gw model     # via gateway
agent claude local qwen   # local model
```

## Install

```bash
git clone https://github.com/YOURUSERNAME/agent.git ~/agent
echo 'source ~/agent/lib/agent.zsh' >> ~/.zshrc
```

## Config

```bash
agent config init    # create config.json
agent config edit    # edit config
```

Requires `jq` and optionally `op` (1Password CLI) or `security` (macOS).