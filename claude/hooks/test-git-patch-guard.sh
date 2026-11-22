#!/usr/bin/env bash
# Tests for git-patch-guard.sh: it refuses git's interactive patch mode
# (`add|checkout|commit|reset|restore -p`, `stash -p`), lets every other git
# command through silently, and the tracked settings register it exactly once
# even when apply-settings.sh runs twice. Never touches the real ~/.claude.
#   bash claude/hooks/test-git-patch-guard.sh
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
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }

run() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$here/git-patch-guard.sh" 2>&1; }

nl=$'\n'
tab=$'\t'
for c in 'git add -p' 'git checkout -p file.sh' 'git checkout -q -p file.sh </dev/null' 'git restore --patch .' \
         'git reset -p HEAD~1' 'git commit -p -m "msg"' 'git stash -p' 'git stash push -p' 'git add -up' \
         'git -C /repo checkout -p' 'git --no-pager -c core.editor=true restore -p x' '/usr/bin/git add -p' \
         'sed -i s/a/b/ f && git checkout -p f; ./test.sh' "echo one${nl}GIT_PAGER=cat git restore -p x" \
         'out=$(git add -p)' 'git restore --source=HEAD~1 -p file' 'if git add -p; then :; fi' 'sudo git add -p' \
         'FOO="a b" BAR=1 git add -p' 'time git checkout -p f' 'git status # see below'"${nl}"'git add -p'; do
  out=$(run "$c"); rc=$?
  if [ "$rc" = 0 ] && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ]
  then ok "refused: $c"; else no "not refused: $c (rc $rc, out '$out')"; fi
done
reason=$(run 'git checkout -p f' | jq -r .hookSpecificOutput.permissionDecisionReason)
case $reason in 'git checkout -p '*) ok "the reason names the subcommand" ;; *) no "reason: $reason" ;; esac

for c in 'git log -p' 'git show -p HEAD' 'git diff -p --stat' 'git stash show -p' 'git stash list -p' \
         'git checkout -b p' 'git checkout -t origin/p' 'git checkout -- -p' 'git add -- -p' 'git reset --hard' \
         'git commit -m "explain -p handling"' "git commit -m 'git add -p is refused'" 'git checkout --progress x' \
         'git add --pathspec-from-file=list' 'git push -u origin topic' 'git --no-pager log -p add' \
         'git -C /repo log -p' 'git add file # then -p by hand' 'mygit add -p' 'git commit -F msg > log-p' \
         "git commit -F - <<'MSG'${nl}git add -p is refused${nl}MSG" 'pacman -Q git; grep -p x' \
         'git --no-pager log --grep add -p -n 1 --oneline' 'echo git add -p' "printf '%s\\n' git add -p" \
         'git status # note | git add -p' 'git status # later; git checkout -p x' "git add${tab}--${tab}-p" \
         'git -p log' 'git -c color.ui=never log -p -- add'; do
  out=$(run "$c"); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "allowed: $c"; else no "not allowed: $c (rc $rc, out '$out')"; fi
done

for input in '{}' '{"tool_name":"Bash"}' 'not json' '{"tool_input":{"command":["git add -p"]}}'; do
  out=$(bash "$here/git-patch-guard.sh" <<<"$input" 2>&1); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "silent on input: $input"; else no "input $input: rc $rc, out '$out'"; fi
done

# Registered once on Bash in the tracked settings, run in place from the repo.
cmd='bash ~/.claude/harness/claude/hooks/git-patch-guard.sh'
count() { jq --arg c "$cmd" '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.command == $c)] | length' "$1"; }
if [ "$(count "$repo/claude/settings.json")" = 1 ]; then ok "tracked settings register the guard on Bash"
else no "tracked settings: guard not registered on Bash"; fi
out=$(jq -n '{tool_name: "Bash", tool_input: {command: "git add -p"}}' | env CLAUDE_CONFIG_DIR="$tmp/elsewhere" sh -c "$cmd" 2>&1)
if [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ]
then ok "registered command denies with a custom CLAUDE_CONFIG_DIR"; else no "registered command: out '$out'"; fi

# apply-settings merges hooks by script name: a re-run must replace, not duplicate.
mkdir -p "$tmp/cfg"
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
if [ "$(count "$tmp/cfg/settings.json" 2>/dev/null)" = 1 ]; then ok "apply-settings twice: one guard"
else no "apply-settings twice: $(count "$tmp/cfg/settings.json" 2>/dev/null) guards"; fi

exit "$fail"
