#!/usr/bin/env bash
# Tests for commit-pipe-guard.sh: it refuses a `git commit` that comes after a
# pipe unless the command turns pipefail on, lets everything else through
# silently, and the tracked settings register it exactly once even when
# apply-settings.sh runs twice. Never touches the real ~/.claude.
#   bash claude/hooks/test-commit-pipe-guard.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
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
fail=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }

run() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$here/commit-pipe-guard.sh" 2>&1; }

nl=$'\n'
# The last one is the documented false refusal: a pipe in an earlier command.
for c in 'bun test | tail -5 && git commit -m x' \
         'psql -f t.sql | grep -v NOTICE | tail && git add -A && git commit -m "x"' \
         "bun test |${nl}tail -3 && git commit -m x" \
         'bun test |& tail && git commit -m x' \
         'bun test | tail && git -C /repo commit -m x' \
         'bun test | tee log || exit 1 && git commit -m x' \
         'set +o pipefail; bun test | tail && git commit -m x' \
         'git commit -m first && bun test | tail && git commit -m second' \
         'bun test | tail && git commit -m x; set -o pipefail' \
         'git status --short | head; git commit -m x'; do
  out=$(run "$c"); rc=$?
  if [ "$rc" = 0 ] && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ] \
     && jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out" | grep -q "set -o pipefail"
  then ok "denied: $c"; else no "not denied: $c (rc $rc, out '$out')"; fi
done

for c in 'git commit -m x' 'git add -A && git commit -m x' \
         'bun test > /tmp/t.log 2>&1 && git commit -m x' \
         'bun test >| /tmp/t.log && git commit -m x' \
         'bun test || exit 1; git commit -m x' \
         'set -o pipefail; bun test | tail -5 && git commit -m x' \
         "set -euo pipefail${nl}bun test | tail -5 && git commit -m x" \
         'set -e -o pipefail && bun test | tail && git commit -m x' \
         'git commit -m x && git log --oneline | head -3' \
         'git add -A && git commit -m "a | b"' \
         "git commit -F - <<'EOF'${nl}check | tail && git commit${nl}EOF" \
         'bun test | tail && git add -A' 'git log --oneline | head -3' 'echo ok'; do
  out=$(run "$c"); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "allowed: $c"; else no "not allowed: $c (rc $rc, out '$out')"; fi
done

for input in '{}' '{"tool_name":"Bash"}' 'not json' '{"tool_input":{"command":["a | b && git commit"]}}' \
             '{"tool_input":{"command":{"a":"a | b && git commit"}}}'; do
  out=$(bash "$here/commit-pipe-guard.sh" <<<"$input" 2>&1); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "silent on input: $input"; else no "input $input: rc $rc, out '$out'"; fi
done

# Registered once on Bash in the tracked settings, run in place from the repo.
cmd='bash ~/.claude/harness/claude/hooks/commit-pipe-guard.sh'
count() { jq --arg c "$cmd" '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.command == $c)] | length' "$1"; }
if [ "$(count "$repo/claude/settings.json")" = 1 ]; then ok "tracked settings register the guard on Bash"
else no "tracked settings: guard not registered on Bash"; fi
out=$(jq -n '{tool_name: "Bash", tool_input: {command: "a | b && git commit -m x"}}' | env CLAUDE_CONFIG_DIR="$tmp/elsewhere" sh -c "$cmd" 2>&1)
if [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ]
then ok "registered command denies with a custom CLAUDE_CONFIG_DIR"; else no "registered command: out '$out'"; fi

# apply-settings merges hooks by script name: a re-run must replace, not
# duplicate, and the pkill guard sharing the Bash group must survive.
mkdir -p "$tmp/cfg"
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
if [ "$(count "$tmp/cfg/settings.json" 2>/dev/null)" = 1 ]; then ok "apply-settings twice: one guard"
else no "apply-settings twice: $(count "$tmp/cfg/settings.json" 2>/dev/null) guards"; fi
if jq -e '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.command | endswith("/pkill-guard.sh"))] | length == 1' \
     "$tmp/cfg/settings.json" >/dev/null 2>&1
then ok "apply-settings twice: the pkill guard is still there, once"; else no "apply-settings twice: pkill guard missing or doubled"; fi

exit "$fail"
