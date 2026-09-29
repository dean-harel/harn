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

# Docs name every command the help text names, and nothing that no longer exists.
for w in "harn login" "harn key" "harn config init" "--show" "brew tap dean-harel/harn https://github.com/dean-harel/harn" "brew install dean-harel/harn/harn"; do
  grep -qF -- "$w" "$ROOT/README.md" && ok "README mentions $w" || bad "README mentions $w"
done
for w in "lib/harn.zsh is sourced" "key_ref" "active.gateway" " -l "; do
  grep -qF -- "$w" "$ROOT/README.md" && bad "README drops $w" || ok "README drops $w"
done
for f in MIGRATION.md CONTRIBUTING.md SECURITY.md .github/ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/feature.yml; do
  [ -f "$ROOT/$f" ] && ok "$f exists" || bad "$f exists"
done

jq -e '.packages["."] | .["release-type"] == "simple" and .["bump-minor-pre-major"] == true
  and (.["extra-files"] | index("bin/harn") and index("Formula/harn.rb"))' \
  "$ROOT/release-please-config.json" >/dev/null 2>&1 && ok "release-please config" || bad "release-please config"
grep -q 'x-release-please-version' "$ROOT/bin/harn" && ok "version marker in bin/harn" || bad "version marker in bin/harn"
grep -q 'tag: "v[0-9.]*" # x-release-please-version' "$ROOT/Formula/harn.rb" 2>/dev/null \
  && ok "version marker in the formula" || bad "version marker in the formula"
