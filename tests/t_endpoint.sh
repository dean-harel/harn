# Endpoint kind: both wires, key variables, defaults, slots, redaction, key_command.

kc=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printf", "%s", "sk-test-1"])
  | .providers["ollama-cloud"] |= (del(.login) | .key_command = ["printf", "%s", "sk-oc-1"])')

OUT=$(HARN_CONFIG="$kc" "$HARN" claude gw --show 2>&1); RC=$?
code "claude gw --show" "$RC" 0
has "labels the gateway" "$OUT" "# source: openrouter (api)"
has "sets base url" "$OUT" "export ANTHROPIC_BASE_URL=https://openrouter.ai/api"
has "redacts key_command" "$OUT" "export ANTHROPIC_AUTH_TOKEN='<redacted: key_command printf %s sk-test-1>'"
has "empties the api key" "$OUT" "export ANTHROPIC_API_KEY=''"
has "uses the default model" "$OUT" "exec claude --model anthropic/claude-sonnet-5"
lacks "--show never resolves the key" "$(printf '%s' "$OUT" | grep -v key_command)" "sk-test-1"

OUT=$(HARN_CONFIG="$kc" "$HARN" claude gw some/model --show -- -p hi 2>&1)
has "explicit model and passthrough" "$OUT" "exec claude --model some/model -p hi"

OUT=$(HARN_CONFIG="$kc" "$HARN" codex gw --show 2>&1)
has "codex key variable" "$OUT" "export OPENROUTER_API_KEY='<redacted: key_command"
has "codex provider injection" "$OUT" "model_providers.openrouter.base_url=https://openrouter.ai/api/v1"
has "codex env_key" "$OUT" "model_providers.openrouter.env_key=OPENROUTER_API_KEY"
has "codex wire_api" "$OUT" "model_providers.openrouter.wire_api=responses"

OUT=$(HARN_CONFIG="$kc" "$HARN" codex ollama-cloud --show 2>&1)
has "hyphenated provider maps to an identifier" "$OUT" "export OLLAMA_CLOUD_API_KEY="
/bin/bash -c 'export OLLAMA_CLOUD_API_KEY=x' && ok "derived name exports under /bin/bash" || bad "derived name exports under /bin/bash"

OUT=$(HARN_CONFIG="$kc" "$HARN" pi gw m --show 2>&1)
has "pi argv" "$OUT" "exec pi --provider openrouter --model m"

OUT=$(HARN_CONFIG="$kc" "$HARN" codex anthropic --show 2>&1); RC=$?
code "missing wire block" "$RC" 2
has "missing wire names the field" "$OUT" "providers.anthropic.openai_wire.base_url"

nodef=$(cfgwith 'del(.providers.openrouter.default_model) | .providers.openrouter |= (del(.login) | .key_command = ["true"])')
OUT=$(HARN_CONFIG="$nodef" "$HARN" claude gw --show 2>&1); RC=$?
code "no model and no default" "$RC" 2
has "names default_model" "$OUT" "providers.openrouter.default_model"

both=$(cfgwith '.providers.openrouter.key_command = ["true"]')
OUT=$(HARN_CONFIG="$both" "$HARN" claude gw --show 2>&1); RC=$?
code "login and key_command both set" "$RC" 2

# Slot swap, compared line by line.
a=$(HARN_CONFIG="$kc" "$HARN" claude gw --show 2>&1)
sw=$(cfgwith '.slots.gw = "ollama-cloud" | .providers.openrouter |= (del(.login) | .key_command = ["printf", "%s", "sk-test-1"]) | .providers["ollama-cloud"] |= (del(.login) | .key_command = ["printf", "%s", "sk-oc-1"])')
b=$(HARN_CONFIG="$sw" "$HARN" claude gw --show 2>&1)
has "swap: new base url" "$b" "ANTHROPIC_BASE_URL=https://ollama.com"
lacks "swap: old base url gone" "$b" "$(printf '%s\n' "$a" | grep '^export ANTHROPIC_BASE_URL')"
has "swap: same key variable" "$b" "export ANTHROPIC_AUTH_TOKEN="
has "swap: new default model" "$b" "exec claude --model glm-5.3-flash"
lacks "swap: nothing from openrouter" "$b" "openrouter"
c=$(HARN_CONFIG="$sw" "$HARN" codex gw --show 2>&1)
has "swap codex: key variable" "$c" "export OLLAMA_CLOUD_API_KEY="
has "swap codex: provider tokens" "$c" "model_provider=ollama-cloud"
lacks "swap codex: nothing from openrouter" "$c" "openrouter"

# Real exec against a stub: key in env, inherited vars cleared.
stub claude 'printf "BASE=%s TOKEN=%s APIKEY=[%s] OAI=%s\n" "$ANTHROPIC_BASE_URL" "$ANTHROPIC_AUTH_TOKEN" "$ANTHROPIC_API_KEY" "${OPENAI_BASE_URL-unset}"; printf "ARGS=%s\n" "$*"'
OUT=$(OPENAI_BASE_URL=https://stale HARN_CONFIG="$kc" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1)
has "real run sets the key" "$OUT" "TOKEN=sk-test-1"
has "real run empties the api key" "$OUT" "APIKEY=[]"
has "real run clears inherited openai vars" "$OUT" "OAI=unset"
lacks "key never on argv" "$(printf '%s' "$OUT" | grep '^ARGS=')" "sk-test-1"

# Review Focus 2: a key_command argument with a space arrives as one argument.
stub printkey 'printf "%s" "$1"'
sp=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printkey", "two words"])')
OUT=$(HARN_CONFIG="$sp" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1)
has "key_command arg with a space" "$OUT" "TOKEN=two words"

fail=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["false"])')
OUT=$(HARN_CONFIG="$fail" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1); RC=$?
code "failing key_command" "$RC" 2
has "failing key_command names the provider" "$OUT" "key_command for 'openrouter' failed"

run claude gw
code "login provider with no stored key" "$RC" 2
has "points at harn login" "$OUT" "run: harn login openrouter"

hn=$(cfgwith '.providers.openrouter.key_command = ["true"] | del(.providers.openrouter.login) | .providers.openrouter.harness_names = {"pi": "or"}')
OUT=$(HARN_CONFIG="$hn" "$HARN" pi gw m --show 2>&1)
has "harness_names renames the provider" "$OUT" "exec pi --provider or --model m"

# An invalid key variable name is a config error naming the field, never a run without the key.
bk=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printf", "k"] | .anthropic_wire.key_env = "BAD NAME")')
stub claude 'echo launched'
OUT=$(HARN_CONFIG="$bk" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1); RC=$?
code "invalid key_env is a config error" "$RC" 2
has "invalid key_env names the field" "$OUT" "providers.openrouter.anthropic_wire.key_env"
lacks "invalid key_env never launches" "$OUT" "launched"
dg=$(cfgwith '.providers["1st"] = (.providers.openrouter | del(.login) | .key_command = ["printf", "k"])')
stub codex 'echo launched'
OUT=$(HARN_CONFIG="$dg" PATH="$STUBS:$PATH" "$HARN" codex 1st 2>&1); RC=$?
code "invalid derived key name is a config error" "$RC" 2
has "invalid derived name says to set key_env" "$OUT" "providers.1st.openai_wire.key_env"

# Review Focus 2: a key_command whose binary is missing is named, and nothing launches.
nk=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["no-such-key-command"])')
OUT=$(HARN_CONFIG="$nk" PATH="$STUBS:$PATH" "$HARN" claude gw 2>&1); RC=$?
code "missing key_command binary" "$RC" 2
has "missing key_command names the provider" "$OUT" "key_command for 'openrouter' failed"

# The retention declaration.
OUT=$(HARN_CONFIG="$kc" "$HARN" claude gw --show 2>&1)
has "undeclared retention" "$OUT" "# retention: not declared"
rt=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["true"] | .retention = "zero, by the workspace guardrail")')
OUT=$(HARN_CONFIG="$rt" "$HARN" claude gw --show 2>&1)
has "declared retention" "$OUT" "# retention: zero, by the workspace guardrail"

# Review Focus 4: a newline in config text cannot become its own line in --show.
nl=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["true"] | .retention = "zero\necho pwned" | .label = "api\necho pwned")')
OUT=$(HARN_CONFIG="$nl" "$HARN" claude gw --show 2>&1)
printf '%s\n' "$OUT" | grep -q '^echo pwned' && bad "newlines stay inside comment lines" "$OUT" || ok "newlines stay inside comment lines"

# Login options.
ob=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce"}')
OUT=$(HARN_CONFIG="$ob" "$HARN" claude gw --show 2>&1)
has "object login without options" "$OUT" "<redacted: login openrouter-pkce>"
ws=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": "ws-uuid-1"}')
OUT=$(HARN_CONFIG="$ws" "$HARN" claude gw --show 2>&1)
has "the redaction shows the workspace" "$OUT" "<redacted: login openrouter-pkce, workspace ws-uuid-1>"
pw=$(cfgwith '.providers["ollama-cloud"].login = {"method": "paste", "workspace": "x"}')
OUT=$(HARN_CONFIG="$pw" "$HARN" claude --show 2>&1); RC=$?
code "workspace on paste is a config error" "$RC" 2
has "workspace on paste names the field" "$OUT" "providers.ollama-cloud.login.workspace"
uo=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "team": "x"}')
OUT=$(HARN_CONFIG="$uo" "$HARN" claude --show 2>&1); RC=$?
code "unknown login option" "$RC" 2
has "unknown login option names the field" "$OUT" "providers.openrouter.login.team"
nm=$(cfgwith '.providers.openrouter.login = {"workspace": "x"}')
OUT=$(HARN_CONFIG="$nm" "$HARN" claude --show 2>&1); RC=$?
code "login object without a method" "$RC" 2
has "missing method names the field" "$OUT" "providers.openrouter.login.method"
ew=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": ""}')
OUT=$(HARN_CONFIG="$ew" "$HARN" claude --show 2>&1); RC=$?
code "empty workspace" "$RC" 2
has "empty workspace names the field" "$OUT" "providers.openrouter.login.workspace"
um=$(cfgwith '.providers.openrouter.login = "sso"')
OUT=$(HARN_CONFIG="$um" "$HARN" claude --show 2>&1); RC=$?
code "unknown login method fails at load" "$RC" 2
has "unknown login method is named" "$OUT" "unknown login 'sso'"

# A redaction pastes as one literal value, whatever the config puts in it.
sd=$(mktemp -d)
for inj in '["sh", "-c", "x; touch INJ #"]' '["sh", "-c", "$(touch INJ)"]' '["sh", "-c", "`touch INJ`"]'; do
  ij=$(cfgwith ".providers.openrouter |= (del(.login) | .key_command = $inj)")
  OUT=$(HARN_CONFIG="$ij" "$HARN" claude gw --show 2>&1)
  (cd "$sd" && printf '%s\n' "$OUT" | grep '^export' | bash >/dev/null 2>&1)
  [ -e "$sd/INJ" ] && bad "key_command redaction pastes inert: $inj" "$OUT" || ok "key_command redaction pastes inert: $inj"
  rm -f "$sd/INJ"
done
ij=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": "w; touch INJ #"}')
OUT=$(HARN_CONFIG="$ij" "$HARN" claude gw --show 2>&1)
(cd "$sd" && printf '%s\n' "$OUT" | grep '^export' | bash >/dev/null 2>&1)
[ -e "$sd/INJ" ] && bad "workspace redaction pastes inert" "$OUT" || ok "workspace redaction pastes inert"

# An empty key_command is named as such.
ek=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = [])')
OUT=$(HARN_CONFIG="$ek" "$HARN" claude gw --show 2>&1); RC=$?
code "empty key_command" "$RC" 2
has "empty key_command is named" "$OUT" "providers.openrouter.key_command is empty"
OUT=$(HARN_CONFIG="$ek" "$HARN" key openrouter 2>&1); RC=$?
code "harn key on an empty key_command" "$RC" 2
has "harn key names the empty key_command" "$OUT" "providers.openrouter.key_command is empty"

# A failing key_command says why.
OUT=$(HARN_CONFIG="$nk" "$HARN" key openrouter 2>&1)
has "failing key_command gives the reason" "$OUT" "executable file not found"

# harn key refuses a provider that sets both credentials, as a run does.
bc=$(cfgwith '.providers.openrouter.key_command = ["true"]')
OUT=$(HARN_CONFIG="$bc" "$HARN" key openrouter 2>&1); RC=$?
code "harn key with both credentials" "$RC" 2
has "harn key names the conflict" "$OUT" "sets both login and key_command"
