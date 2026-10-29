#!/usr/bin/env bash
# Tests for pkill-guard.sh: it refuses `pkill -f` / `pgrep -f` without a
# bracketed pattern, lets everything else through silently, and the tracked
# settings register it exactly once even when apply-settings.sh runs twice.
# Never touches the real ~/.claude.
#   bash claude/hooks/test-pkill-guard.sh
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

run() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$here/pkill-guard.sh" 2>&1; }

nl=$'\n'
for c in 'pkill -f "next dev"' 'pkill -f next-server' 'sleep 1; pkill -9 -f "next dev"; echo done' \
         'pgrep -af "next-server|next dev" | xargs kill' 'pkill -u me -f node' 'pkill --full "bun dev"' \
         'cd /tmp && pgrep -fl vite' "pkill -f '[n]ext dev'; pkill -f node" "pkill -f node; pgrep -f '[n]ext'" \
         "pkill -f node; echo 'pgrep [x]'" '/usr/bin/pkill -f node' './pkill -f node' 'kill $(pgrep -f next)' \
         'kill `pgrep -f next`' 'sudo pkill -f node' 'timeout 5 pkill -f node' "echo start${nl}pkill -f node" \
         'sudo -u root pkill -f node' 'if pgrep -f node; then echo running; fi' \
         'for name in node; do pkill -f "$name"; done' 'pkill -fu1000 node' 'pgrep -fP1234 node' \
         "pkill \\${nl}-f node" 'pkill -f node # [n]' 'pkill -f node > /tmp/kill[1].log'; do
  out=$(run "$c"); rc=$?
  if [ "$rc" = 0 ] && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ] \
     && jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out" | grep -q "kill it in its own call"
  then ok "denied: $c"; else no "not denied: $c (rc $rc, out '$out')"; fi
done

for c in "pkill -f '[n]ext dev'" 'pgrep -af "[n]ext-server"' 'kill 606638' 'pgrep -x node' 'pkill node' \
         'pgrep -l firefox' 'ss -ltnp | grep :3000' 'git log -f' 'echo ok' 'tail -f app.log' \
         "printf '%s\n' 'pkill -f node'" "# pkill -f node${nl}echo ok" "pgrep -x node${nl}tail -f app.log" \
         'grep -n "pkill -f" notes.md' "printf '%s\n' 'example; pkill -f node'" \
         "cat > /tmp/notes.md <<'EOF'${nl}pkill -f node${nl}EOF${nl}echo written" "pkill -f 'foo([b]ar)'" \
         "pgrep -x 'node -f worker'" 'pkill -f [n]ode'; do
  out=$(run "$c"); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "allowed: $c"; else no "not allowed: $c (rc $rc, out '$out')"; fi
done

for input in '{}' '{"tool_name":"Bash"}' 'not json' '{"tool_input":{"command":["pkill -f node"]}}' \
             '{"tool_input":{"command":{"a":"pkill -f node"}}}'; do
  out=$(bash "$here/pkill-guard.sh" <<<"$input" 2>&1); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "silent on input: $input"; else no "input $input: rc $rc, out '$out'"; fi
done

# Registered once on Bash in the tracked settings, run in place from the repo.
cmd='bash ~/.claude/harness/claude/hooks/pkill-guard.sh'
count() { jq --arg c "$cmd" '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.command == $c)] | length' "$1"; }
if [ "$(count "$repo/claude/settings.json")" = 1 ]; then ok "tracked settings register the guard on Bash"
else no "tracked settings: guard not registered on Bash"; fi
out=$(jq -n '{tool_name: "Bash", tool_input: {command: "pkill -f x"}}' | env CLAUDE_CONFIG_DIR="$tmp/elsewhere" sh -c "$cmd" 2>&1)
if [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ]
then ok "registered command denies with a custom CLAUDE_CONFIG_DIR"; else no "registered command: out '$out'"; fi

# apply-settings merges hooks by script name: a re-run must replace, not duplicate.
mkdir -p "$tmp/cfg"
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
if [ "$(count "$tmp/cfg/settings.json" 2>/dev/null)" = 1 ]; then ok "apply-settings twice: one guard"
else no "apply-settings twice: $(count "$tmp/cfg/settings.json" 2>/dev/null) guards"; fi

exit "$fail"
