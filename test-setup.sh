#!/usr/bin/env bash
# Exercise setup against old links and fresh homes, without machine state.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/home/.claude" CODEX_HOME="$tmp/home/.codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR/skills" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
for command in claude codex systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
printf '#!/usr/bin/env bash\nprintf "claude: current\\ncodex: current\\n"\n' > "$tmp/bin/herdr"
chmod +x -- "$tmp"/bin/*
export PATH="$tmp/bin:$PATH"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
setup() {
  if bash -- "$repo/setup.sh" "$@" > "$tmp/output" 2>&1; then return 0; fi
  no "setup.sh $*"
  cat -- "$tmp/output"
  return 1
}

# Today's links can be dangling: the old dotfiles clone need not be present.
ln -s -- "$HOME/.config/claude/CLAUDE.global.md" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
ln -s -- "$HOME/.config/claude/skills/delegate" "$CLAUDE_CONFIG_DIR/skills/delegate"
ln -s -- "$HOME/.config/codex/AGENTS.global.md" "$CODEX_HOME/AGENTS.md"
ln -s -- "$repo/claude/skills/removed" "$CLAUDE_CONFIG_DIR/skills/removed"
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{
  "advisorModel": "fable",
  "keepMe": 1,
  "statusLine": {"type": "command", "command": "bash ~/.config/claude/statusline.sh"},
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "bash '/x/herdr-agent-state.sh' session"}]}],
    "PreToolUse": [{"matcher": "Agent", "hooks": [{"type": "command", "command": "sh ~/.config/claude/hooks/agent-guard.sh"}]}]
  }
}
JSON
chmod 640 -- "$CLAUDE_CONFIG_DIR/settings.json"
cp -p -- "$CLAUDE_CONFIG_DIR/settings.json" "$tmp/mode-reference"
setup
if [ "$(readlink "$CLAUDE_CONFIG_DIR/CLAUDE.md")" = "$repo/claude/CLAUDE.global.md" ] \
   && [ "$(readlink "$CLAUDE_CONFIG_DIR/skills/delegate")" = "$repo/claude/skills/delegate" ] \
   && [ "$(readlink "$CODEX_HOME/AGENTS.md")" = "$repo/codex/AGENTS.global.md" ]; then
  ok 'upgrade: CLAUDE.md, skills/delegate and AGENTS.md link into the new clone'
else no 'upgrade: CLAUDE.md, skills/delegate and AGENTS.md link into the new clone'; fi

if jq -e 'has("advisorModel") == false and .keepMe == 1
  and ([.hooks.SessionStart[].hooks[].command] == ["bash '\''/x/herdr-agent-state.sh'\'' session",
    "sh ~/.claude/harness/claude/hooks/advisor-reset.sh"])' \
  "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null; then
  ok 'upgrade: advisorModel removed, keepMe kept, herdr hook kept'
else no 'upgrade: advisorModel removed, keepMe kept, herdr hook kept'; fi

commands_correct() {
  jq -e '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("agent-guard.sh"))] as $guards
    | ($guards | length) == 1
      and $guards[0].command == "sh ~/.claude/harness/claude/hooks/agent-guard.sh"
      and .statusLine.command == "bash ~/.claude/harness/claude/statusline.sh"' "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null
}
if commands_correct; then
  ok 'upgrade: exactly one guard hook, naming ~/.claude/harness; status line names ~/.claude/harness'
else no 'upgrade: exactly one guard hook, naming ~/.claude/harness; status line names ~/.claude/harness'; fi

if [ ! -L "$CLAUDE_CONFIG_DIR/skills/removed" ]; then ok 'upgrade: dangling harness links removed'
else no 'upgrade: dangling harness links removed'; fi
mode=$(LC_ALL=C ls -ld -- "$CLAUDE_CONFIG_DIR/settings.json")
reference=$(LC_ALL=C ls -ld -- "$tmp/mode-reference")
if [ "${mode%% *}" = "${reference%% *}" ]; then ok 'upgrade: settings mode preserved'
else no 'upgrade: settings mode preserved'; fi

cp -p -- "$CLAUDE_CONFIG_DIR/settings.json" "$tmp/once.json"
setup
if cmp -s -- "$tmp/once.json" "$CLAUDE_CONFIG_DIR/settings.json"; then ok 'upgrade: settings unchanged on second run'
else no 'upgrade: settings unchanged on second run'; fi

export HOME="$tmp/fresh" CLAUDE_CONFIG_DIR="$tmp/fresh/.claude" CODEX_HOME="$tmp/fresh/.codex"
setup --dry-run
if [ ! -e "$HOME" ]; then ok 'fresh: dry run leaves home absent'
else no 'fresh: dry run leaves home absent'; fi
setup
if [ "$(readlink "$HOME/.claude/harness")" = "$repo" ]; then ok 'fresh: ~/.claude/harness points at the clone'
else no 'fresh: ~/.claude/harness points at the clone'; fi

# The stable command path stays in ~/.claude with a custom config directory.
export HOME="$tmp/custom" CLAUDE_CONFIG_DIR="$tmp/custom-config" CODEX_HOME="$tmp/custom-codex"
mkdir -p -- "$HOME/.claude"
printf 'keep this file\n' > "$HOME/.claude/harness"
setup
if [ "$(readlink "$HOME/.claude/harness")" = "$repo" ] && commands_correct \
   && [ "$(readlink "$CLAUDE_CONFIG_DIR/CLAUDE.md")" = "$repo/claude/CLAUDE.global.md" ]; then
  ok 'custom config: stable harness link and configured instruction link'
else no 'custom config: stable harness link and configured instruction link'; fi
saved=false
for backup in "$XDG_STATE_HOME"/dotfiles-agents-backup/*/.claude/harness*; do
  if [ -f "$backup" ] && [ "$(cat -- "$backup")" = 'keep this file' ]; then saved=true; fi
done
if "$saved"; then ok 'custom config: existing harness file backed up'
else no 'custom config: existing harness file backed up'; fi

exit "$fail"
