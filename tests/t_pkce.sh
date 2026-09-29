# OpenRouter PKCE login against a stub curl.

OUT=$(HARN_PKCE_SELFTEST=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk "$HARN" --pkce-selftest 2>&1)
has "RFC 7636 appendix B challenge" "$OUT" "challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
v=$(printf '%s\n' "$OUT" | sed -n 's/^verifier=//p')
printf '%s' "$v" | grep -Eq '^[A-Za-z0-9_-]{64}$' && ok "generated verifier shape" || bad "generated verifier shape" "$v"

rec=$(mktemp -d)
stub curl "printf '%s\n' \"\$@\" > '$rec/argv'; cat > '$rec/stdin'; printf '{\"key\":\"sk-or-from-pkce\"}'"
stub open "echo opened >> '$rec/opened'; exit 1"
stub xdg-open "echo opened >> '$rec/opened'; exit 1"
OUT=$(printf 'the-code-123\n' | PATH="$STUBS:$PATH" "$HARN" login openrouter --no-open 2>&1); RC=$?
code "pkce login exits 0" "$RC" 0
has "prints the auth URL" "$OUT" "https://openrouter.ai/auth?code_challenge="
has "URL uses S256" "$OUT" "code_challenge_method=S256"
has "URL labels the key" "$OUT" "key_label=harn-"
has "posts to the keys endpoint" "$(cat "$rec/argv")" "https://openrouter.ai/api/v1/auth/keys"
has "uses POST" "$(cat "$rec/argv")" "POST"
has "body carries the code" "$(cat "$rec/stdin")" '"code":"the-code-123"'
has "body carries S256" "$(cat "$rec/stdin")" '"code_challenge_method":"S256"'
body_v=$(jq -r .code_verifier "$rec/stdin")
[ "${#body_v}" = 64 ] && ok "body carries the verifier" || bad "body carries the verifier" "$body_v"
lacks "code not on argv" "$(cat "$rec/argv")" "the-code-123"
lacks "verifier not on argv" "$(cat "$rec/argv")" "$body_v"
[ -e "$rec/opened" ] && bad "--no-open opens nothing" || ok "--no-open opens nothing"
run key openrouter
has "stored the returned key" "$OUT" "sk-or-from-pkce"

stub curl "cat > /dev/null; printf '{\"error\":{\"message\":\"invalid code\"}}'"
OUT=$(printf 'bad\n' | PATH="$STUBS:$PATH" "$HARN" login openrouter --no-open 2>&1); RC=$?
code "response without key" "$RC" 2
has "shows the API error" "$OUT" "invalid code"
rm -f "$XDG_STATE_HOME/harn/keys/openrouter"
