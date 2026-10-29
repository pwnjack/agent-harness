#!/usr/bin/env bash
# Merge the tracked fragments in an isolated Codex home.
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

printf '[features]\nhooks = true\n' > "$CODEX_HOME/config.toml"
if bash "$here/apply-config.sh" > "$tmp/merge-output" 2>&1 \
   && grep -qx 'memories = false' "$CODEX_HOME/config.toml" \
   && grep -qx 'hooks = true' "$CODEX_HOME/config.toml" \
   && [ "$(grep -c '^\[features\]$' "$CODEX_HOME/config.toml")" = 1 ]; then
  ok "merge: memories off and existing hooks kept"
else no "merge: memories off and existing hooks kept"; fi
cp -- "$CODEX_HOME/config.toml" "$tmp/first.toml"
if bash "$here/apply-config.sh" > "$tmp/merge-output" 2>&1 \
   && cmp -s -- "$tmp/first.toml" "$CODEX_HOME/config.toml"; then
  ok "second merge: config byte-identical"
else no "second merge: config byte-identical"; fi

cp -- "$here/testdata/full-config.toml" "$CODEX_HOME/config.toml"
if bash "$here/apply-config.sh" > "$tmp/merge-output" 2>&1 \
   && cmp -s -- "$here/testdata/full-config.expected.toml" "$CODEX_HOME/config.toml"; then
  ok "full config: only tracked keys change"
else no "full config: only tracked keys change"; fi
if bash "$here/apply-config.sh" > "$tmp/merge-output" 2>&1 \
   && cmp -s -- "$here/testdata/full-config.expected.toml" "$CODEX_HOME/config.toml"; then
  ok "full config: second merge identical"
else no "full config: second merge identical"; fi

exit "$fail"
