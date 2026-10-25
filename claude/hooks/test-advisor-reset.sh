#!/usr/bin/env bash
# Advisor choices last one interactive session; workers leave them alone.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME/.claude" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
ln -s -- "$repo" "$HOME/.claude/harness"
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
printf '#!/usr/bin/env bash\nprintf "claude: current\\ncodex: current\\n"\n' > "$tmp/bin/herdr"
chmod +x -- "$tmp"/bin/*
export PATH="$tmp/bin:$PATH"
unset HARNESS_LEAF
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
target="$CLAUDE_CONFIG_DIR/settings.json"
hook="$here/advisor-reset.sh"
cmd='sh ~/.claude/harness/claude/hooks/advisor-reset.sh'
silent_success() { local out; out=$("$@" 2>&1) && [ -z "$out" ]; }

printf '{"advisorModel":"sonnet","model":"opus","env":{"KEEP":"yes"}}\n' > "$target"
chmod 640 -- "$target"
cp -p -- "$target" "$tmp/before.json"
mode=$(ls -ld -- "$target"); mode=${mode%% *}
if silent_success sh "$hook" \
   && jq -e '. == {"model":"opus","env":{"KEEP":"yes"}}' "$target" >/dev/null 2>&1 \
   && [ "$(ls -ld -- "$target" | cut -d ' ' -f 1)" = "$mode" ]; then
  ok "advisorModel removed, other keys and mode kept"
else no "advisorModel removed, other keys and mode kept"; fi

cp -- "$tmp/before.json" "$target"
if silent_success env HARNESS_LEAF=1 sh "$hook" && cmp -s -- "$tmp/before.json" "$target"; then
  ok "HARNESS_LEAF=1: file byte-identical"
else no "HARNESS_LEAF=1: file byte-identical"; fi

printf '{ "model": "opus", "env": {} }\n' > "$target"
cp -- "$target" "$tmp/before.json"
if silent_success sh "$hook" && cmp -s -- "$tmp/before.json" "$target"; then
  ok "no advisorModel: file byte-identical"
else no "no advisorModel: file byte-identical"; fi

for settings in '{not json' '[]' 'null' '42' '{"advisorModel":"sonnet"} {"advisorModel":"opus"}'; do
  printf '%s\n' "$settings" > "$target"
  cp -- "$target" "$tmp/before.json"
  if silent_success sh "$hook" && cmp -s -- "$tmp/before.json" "$target"; then
    ok "invalid settings ($settings): exit 0, file untouched"
  else no "invalid settings ($settings): exit 0, file untouched"; fi
done
rm -f -- "$target"
if silent_success sh "$hook" && [ ! -e "$target" ]; then
  ok "missing settings: exit 0, no file created"
else no "missing settings: exit 0, no file created"; fi

printf '{"advisorModel":"sonnet","model":"opus"}\n' > "$HOME/.claude/settings.json"
if silent_success env -u CLAUDE_CONFIG_DIR sh "$hook" \
   && jq -e '. == {"model":"opus"}' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  ok "unset CLAUDE_CONFIG_DIR: uses HOME/.claude"
else no "unset CLAUDE_CONFIG_DIR: uses HOME/.claude"; fi

count() { jq --arg c "$cmd" '[.hooks.SessionStart[]? | select(.matcher == "startup") | .hooks[] | select(.command == $c)] | length' "$1"; }
if [ "$(count "$repo/claude/settings.json")" = 1 ]; then
  ok "tracked settings register it once under SessionStart startup"
else no "tracked settings register it once under SessionStart startup"; fi
reg=$(jq -r '[.hooks.SessionStart[]? | select(.matcher == "startup") | .hooks[].command | select(endswith("/advisor-reset.sh"))] | first // "false"' "$repo/claude/settings.json")
printf '{"advisorModel":"sonnet","model":"opus"}\n' > "$target"
if silent_success sh -c "$reg" && jq -e '. == {"model":"opus"}' "$target" >/dev/null 2>&1; then
  ok "registered command resets a custom CLAUDE_CONFIG_DIR"
else no "registered command resets a custom CLAUDE_CONFIG_DIR"; fi
if bash "$repo/claude/apply-settings.sh" > "$tmp/merge-output" 2>&1 \
   && bash "$repo/claude/apply-settings.sh" > "$tmp/merge-output" 2>&1 \
   && [ "$(count "$target")" = 1 ]; then
  ok "apply-settings twice: one reset hook"
else no "apply-settings twice: one reset hook"; fi

exit "$fail"
