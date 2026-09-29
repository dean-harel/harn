# File key store, paste login, harn key.

printf 'sk-oc-pasted \n' | "$HARN" login ollama-cloud >/dev/null 2>&1
code "paste login exits 0" "$?" 0
f="$XDG_STATE_HOME/harn/keys/ollama-cloud"
[ -f "$f" ] && ok "key file written" || bad "key file written"
perm=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")
code "key file is 0600" "$perm" 600
# Review Focus 4: byte-exact round trip: 13 bytes, the last one the trailing space, no newline added.
code "stored key is 13 bytes" "$(wc -c < "$f" | tr -d ' ')" 13
[ "$(tail -c 1 "$f")" = " " ] && ok "trailing space kept, no newline" || bad "trailing space kept, no newline" "$(od -c "$f")"

run key ollama-cloud
code "harn key exits 0" "$RC" 0
has "harn key prints the key" "$OUT" "sk-oc-pasted"

stub claude 'printf "TOKEN=[%s]\n" "$ANTHROPIC_AUTH_TOKEN"'
OUT=$(PATH="$STUBS:$PATH" "$HARN" claude ollama-cloud 2>&1)
has "endpoint uses the stored key" "$OUT" "TOKEN=[sk-oc-pasted ]"

run claude ollama-cloud --show
has "paste redaction" "$OUT" "<redacted: login paste>"

kc=$(cfgwith '.providers.openrouter |= (del(.login) | .key_command = ["printf", "%s", "from-cmd"])')
OUT=$(HARN_CONFIG="$kc" "$HARN" key openrouter 2>&1)
has "harn key runs key_command" "$OUT" "from-cmd"

printf 'sk-oc-second' | "$HARN" login ollama-cloud >/dev/null 2>&1
run key ollama-cloud
has "a second login overwrites the key" "$OUT" "sk-oc-second"
rm -f "$f"
run key ollama-cloud
code "key after the file is deleted" "$RC" 2
has "missing key points at login" "$OUT" "run: harn login ollama-cloud"

printf '\n' | "$HARN" login ollama-cloud >/dev/null 2>&1
code "empty paste is refused" "$?" 2

run login nope
code "login for an unknown provider" "$RC" 2
