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

# Docs name every command the help text names.
for w in "harn login" "harn key" "harn config init" "--show"; do
  grep -qF -- "$w" "$ROOT/README.md" && ok "README mentions $w" || bad "README mentions $w"
done
for f in CONTRIBUTING.md SECURITY.md .github/ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/feature.yml; do
  [ -f "$ROOT/$f" ] && ok "$f exists" || bad "$f exists"
done

# Installed from source: no release machinery.
for f in .github/workflows/release.yml release-please-config.json .release-please-manifest.json Formula/harn.rb; do
  [ ! -e "$ROOT/$f" ] && ok "no $f" || bad "no $f"
done
[ ! -e "$ROOT/bin/harn" ] && ok "the bash script is gone" || bad "the bash script is gone"
grep -qF 'go install github.com/dean-harel/harn@latest' "$ROOT/README.md" && ok "README names go install" || bad "README names go install"

# Review Focus 5: comments and trailing commas parse; invalid JSON is a config error naming the file.
cm=$(mktemp)
cat > "$cm" <<'EOF'
{
  // the everyday account
  "harness": { "claude": { "wire": "anthropic", "binary": "claude", "account": true, }, },
}
EOF
OUT=$(HARN_CONFIG="$cm" "$HARN" claude --show 2>&1); RC=$?
code "config with comments and trailing commas" "$RC" 0
OUT=$(HARN_CONFIG="$cm" "$HARN" config 2>&1)
has "config prints the file as written" "$OUT" "// the everyday account"
iv=$(mktemp); printf '{"slots": ' > "$iv"
OUT=$(HARN_CONFIG="$iv" "$HARN" claude --show 2>&1); RC=$?
code "invalid config" "$RC" 2
has "invalid config names the file" "$OUT" "$iv is not valid config"
