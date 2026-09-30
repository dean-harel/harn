# Launcher kind.

run claude local qwen3-coder --show
code "claude local --show" "$RC" 0
has "labels local" "$OUT" "# source: ollama (local)"
has "launcher argv" "$OUT" "exec ollama launch claude --model qwen3-coder"

run codex local qwen3-coder --show -- -p "hi there"
has "launcher passthrough after --" "$OUT" "exec ollama launch codex --model qwen3-coder -- -p hi\\ there"

run pi local --show
code "launcher without a model" "$RC" 0
has "no --model leaves the picker" "$OUT" "exec ollama launch pi"
lacks "no --model flag" "$OUT" "--model"

stub ollama 'printf "OAI=%s ARGS=%s\n" "${OPENAI_API_KEY-unset}" "$*"'
OUT=$(OPENAI_API_KEY=stale PATH="$STUBS:$PATH" "$HARN" codex local m 2>&1)
has "launcher clears inherited keys" "$OUT" "OAI=unset"
has "launcher real argv" "$OUT" "ARGS=launch codex --model m"

str=$(cfgwith '.providers.ollama.launcher = "ollama launch"')
OUT=$(HARN_CONFIG="$str" "$HARN" claude local m --show 2>&1); RC=$?
code "string launcher is a config error" "$RC" 2
has "names the launcher field" "$OUT" "providers.ollama.launcher"

run claude local m --show
lacks "a launcher run declares no retention" "$OUT" "# retention:"
