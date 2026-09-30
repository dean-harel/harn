# OpenRouter PKCE login from outside; the code exchange and the PKCE math are in pkce_test.go.

rec=$(mktemp -d)
stub open "echo opened >> '$rec/opened'; exit 1"
stub xdg-open "echo opened >> '$rec/opened'; exit 1"
OUT=$(printf '\n' | PATH="$STUBS:$PATH" "$HARN" login openrouter --no-open 2>&1); RC=$?
code "an empty code is refused" "$RC" 2
has "refusal names the missing code" "$OUT" "no code entered"
has "prints the auth URL" "$OUT" "https://openrouter.ai/auth?code_challenge="
has "URL uses S256" "$OUT" "code_challenge_method=S256"
has "URL labels the key" "$OUT" "key_label=harn-"
[ -e "$rec/opened" ] && bad "--no-open opens nothing" || ok "--no-open opens nothing"

OUT=$(printf '\n' | "$HARN" login openrouter --bogus 2>&1); RC=$?
code "unknown login flag" "$RC" 2
has "unknown login flag is named" "$OUT" "unknown flag: --bogus"

# The workspace pin reaches the authorization URL.
ws=$(cfgwith '.providers.openrouter.login = {"method": "openrouter-pkce", "workspace": "ws-uuid-1"}')
OUT=$(printf '\n' | HARN_CONFIG="$ws" "$HARN" login openrouter --no-open 2>&1)
has "URL pins the workspace" "$OUT" "required_workspace_id=ws-uuid-1"
OUT=$(printf '\n' | "$HARN" login openrouter --no-open 2>&1)
lacks "no pin without a workspace" "$OUT" "required_workspace_id"
