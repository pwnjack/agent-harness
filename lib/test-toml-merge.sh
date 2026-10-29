#!/usr/bin/env bash
# Merge fragments with multi-line values into scratch TOML files.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
printf '#!/usr/bin/env bash\nprintf "claude: current\\ncodex: current\\n"\n' > "$tmp/bin/herdr"
chmod +x -- "$tmp"/bin/*
export PATH="$tmp/bin:$PATH"
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
merge() { bash "$here/toml-merge.sh" test "$tmp/target.toml" "$tmp/fragment.toml" > "$tmp/output" 2>&1; }

cat > "$tmp/fragment.toml" <<'EOF'
# a comment above the table
[ui]
rows = [
  ["a", "b"],
]
EOF
printf '[ui]\nrows = ["old"]\nwidth = 30\n' > "$tmp/target.toml"
printf '[ui]\nrows = [\n  ["a", "b"],\n]\nwidth = 30\n' > "$tmp/expected.toml"
if merge && cmp -s -- "$tmp/expected.toml" "$tmp/target.toml" \
   && [ "$(cat -- "$tmp/output")" = "test: merged fragment.toml into $tmp/target.toml" ]; then
  ok "multi-line fragment value replaces a one-line target value"
else no "multi-line fragment value replaces a one-line target value"; fi

printf '[ui]\nrows = [\n  ["x"],\n  ["y"],\n]\nwidth = 30\n' > "$tmp/target.toml"
if merge && cmp -s -- "$tmp/expected.toml" "$tmp/target.toml"; then
  ok "multi-line fragment value replaces a multi-line target value"
else no "multi-line fragment value replaces a multi-line target value"; fi

printf '[other]\nkeep = 1\n' > "$tmp/target.toml"
printf '[other]\nkeep = 1\n\n[ui]\nrows = [\n  ["a", "b"],\n]\n' > "$tmp/expected.toml"
if merge && cmp -s -- "$tmp/expected.toml" "$tmp/target.toml"; then
  ok "multi-line fragment key appended to a missing table"
else no "multi-line fragment key appended to a missing table"; fi

cp -- "$tmp/target.toml" "$tmp/first.toml"
if merge && cmp -s -- "$tmp/first.toml" "$tmp/target.toml" \
   && [ "$(cat -- "$tmp/output")" = "test: target.toml already up to date" ]; then
  ok "second merge byte-identical"
else no "second merge byte-identical"; fi

cat > "$tmp/fragment.toml" <<'EOF'
[ui]
rows = [
  ["a", { token = "$x", rules = [{ equals = "y", fg = "#fff" }] }],
]
EOF
printf '[ui]\nrows = []\nwidth = 30\n' > "$tmp/target.toml"
{ printf '[ui]\n'; tail -n +2 -- "$tmp/fragment.toml"; printf 'width = 30\n'; } > "$tmp/expected.toml"
if merge && cmp -s -- "$tmp/expected.toml" "$tmp/target.toml" \
   && merge && cmp -s -- "$tmp/expected.toml" "$tmp/target.toml"; then
  ok "inline tables on fragment lines kept verbatim"
else no "inline tables on fragment lines kept verbatim"; fi

printf '[ui]\nrows = []\n' > "$tmp/target.toml"
chmod 600 -- "$tmp/target.toml"
ln -- "$tmp/target.toml" "$tmp/link.toml"
if merge && cmp -s -- "$tmp/link.toml" "$tmp/target.toml" \
   && [ "$(ls -l -- "$tmp/target.toml" | cut -c1-10)" = '-rw-------' ]; then
  ok "rewritten in place: inode and mode kept"
else no "rewritten in place: inode and mode kept"; fi

rm -f -- "$tmp/target.toml" "$tmp/link.toml"
if merge && [ -f "$tmp/target.toml" ] && [ "$(head -n 1 -- "$tmp/target.toml")" = '[ui]' ]; then
  ok "missing target created"
else no "missing target created"; fi

if ! bash "$here/toml-merge.sh" test "$tmp/absent/target.toml" "$tmp/fragment.toml" > "$tmp/output" 2>&1 \
   && grep -q '^test: ' "$tmp/output"; then
  ok "write error: non-zero with a message"
else no "write error: non-zero with a message"; fi

exit "$fail"
