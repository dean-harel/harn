# Config subcommands, help, symlinked install, old-install stub.

run config
code "config prints" "$RC" 0
has "config prints providers" "$OUT" '"providers"'

d=$(mktemp -d)
OUT=$(HARN_CONFIG="$d/config.json" "$HARN" config init 2>&1); RC=$?
code "init writes" "$RC" 0
jq -e '.slots.gw == "openrouter"' "$d/config.json" >/dev/null && ok "init content" || bad "init content"
OUT=$(HARN_CONFIG="$d/config.json" "$HARN" config init 2>&1); RC=$?
code "init refuses to overwrite" "$RC" 2
has "init names --force" "$OUT" "--force"
OUT=$(HARN_CONFIG="$d/config.json" "$HARN" config init --force 2>&1); RC=$?
code "init --force overwrites" "$RC" 0

# Review Focus 5: a symlinked binary still finds the template.
ln -s "$HARN" "$d/harn"
OUT=$(HARN_CONFIG="$d/new.json" "$d/harn" config init 2>&1); RC=$?
code "symlinked init" "$RC" 0
[ -f "$d/new.json" ] && ok "symlinked init wrote the template" || bad "symlinked init wrote the template"

run --help
code "help exits 0" "$RC" 0
has "help shows usage" "$OUT" "usage: harn <harness>"
has "help lists login" "$OUT" "harn login <provider>"

if command -v zsh >/dev/null 2>&1; then
  OUT=$(zsh -c "source '$ROOT/lib/harn.zsh'" 2>&1)
  has "stub tells old installs what to change" "$OUT" "put bin/harn on your PATH"
fi
