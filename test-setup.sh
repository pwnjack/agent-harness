#!/usr/bin/env bash
# Exercise setup against old links and fresh homes, without machine state.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/home/.claude" CODEX_HOME="$tmp/home/.codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR/skills" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
for command in codex ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
cat > "$tmp/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${CLAUDE_CONFIG_DIR-UNSET}" >> "$TEST_CLAUDE_CONFIG_LOG"
SH
export TEST_CLAUDE_CONFIG_LOG="$tmp/claude-config.log"
cat > "$tmp/bin/uname" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${TEST_UNAME:-Linux}"
SH
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${TEST_VISIBILITY:-PRIVATE}"
SH
cat > "$tmp/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
SH
export TEST_SYSTEMCTL_LOG="$tmp/systemctl.log"
: > "$TEST_SYSTEMCTL_LOG"
printf '#!/usr/bin/env bash\nprintf "claude: current\\ncodex: current\\n"\n' > "$tmp/bin/herdr"
chmod +x -- "$tmp"/bin/*
export PATH="$tmp/bin:$PATH"

# Setup configures the clone's hooks, so exercise a disposable clone too.
source_repo=$repo
prepare_clone() {
  repo=$1
  mkdir -p -- "$repo" || return 1
  cp -- "$source_repo/setup.sh" "$repo/setup.sh" || return 1
  for directory in claude codex brain githooks; do
    cp -R -- "$source_repo/$directory" "$repo/$directory" || return 1
  done
  git init -q -b main -- "$repo"
}
prepare_clone "$tmp/clone" || exit 1

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

if [ "$(git -C "$repo" config --local core.hooksPath)" = githooks ]; then
  ok 'plain setup: harness hooks configured'
else no 'plain setup: harness hooks configured'; fi
if [ ! -e "$CLAUDE_CONFIG_DIR/projects/.git" ] \
   && [ ! -e "$XDG_CONFIG_HOME/systemd/user/brain-commit.service" ] \
   && [ ! -e "$XDG_STATE_HOME/agent-brain.git" ] \
   && [ ! -s "$TEST_SYSTEMCTL_LOG" ] \
   && jq -e 'has("autoDreamEnabled") | not' "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null; then
  ok 'plain setup: no brain repository, units, timer or auto-dream'
else no 'plain setup: no brain repository, units, timer or auto-dream'; fi

brain_home() {
  export HOME="$tmp/brain-$1" CLAUDE_CONFIG_DIR="$tmp/brain-$1/config"
  export CODEX_HOME="$tmp/brain-$1/codex" XDG_STATE_HOME="$tmp/brain-$1/state"
  export XDG_CONFIG_HOME="$tmp/brain-$1/xdg-config"
  : > "$TEST_SYSTEMCTL_LOG"
}
refused() {
  if bash -- "$repo/setup.sh" --brain > "$tmp/output" 2>&1; then
    no "$1"
  elif [ ! -e "$HOME" ] && [ ! -s "$TEST_SYSTEMCTL_LOG" ]; then
    ok "$1"
  else no "$1"; fi
}
brain_home darwin
TEST_UNAME=Darwin refused 'brain: Darwin refused without creating anything'
brain_home public
TEST_VISIBILITY=PUBLIC refused 'brain: public remote refused without creating anything'
brain_home missing-gh
# A minimal PATH ensures an installed gh cannot hide this missing dependency.
mkdir -p -- "$tmp/no-gh"
for command in date dirname jq uname; do
  ln -s -- "$(command -v "$command")" "$tmp/no-gh/$command"
done
bash_path=$(command -v bash)
ln -s -- "$bash_path" "$tmp/no-gh/bash"
if PATH="$tmp/no-gh" "$bash_path" "$repo/setup.sh" --brain > "$tmp/output" 2>&1; then
  no 'brain: missing gh refused without creating anything'
elif [ ! -e "$HOME" ] && [ ! -s "$TEST_SYSTEMCTL_LOG" ] \
   && grep -qF -- '--brain requires gh' "$tmp/output"; then
  ok 'brain: missing gh refused without creating anything'
else no 'brain: missing gh refused without creating anything'; fi

brain_home directory
mkdir -p -- "$CLAUDE_CONFIG_DIR/projects"
git init -q -b main -- "$CLAUDE_CONFIG_DIR/projects"
printf 'untouched\n' > "$CLAUDE_CONFIG_DIR/projects/.git/sentinel"
cp -- "$CLAUDE_CONFIG_DIR/projects/.git/config" "$tmp/original-config"
if bash -- "$repo/setup.sh" --brain > "$tmp/output" 2>&1; then
  no 'brain: existing .git directory refused unchanged'
elif cmp -s -- "$tmp/original-config" "$CLAUDE_CONFIG_DIR/projects/.git/config" \
   && [ "$(cat -- "$CLAUDE_CONFIG_DIR/projects/.git/sentinel")" = untouched ] \
   && [ ! -e "$HOME/.claude" ] && [ ! -e "$XDG_STATE_HOME" ]; then
  ok 'brain: existing .git directory refused unchanged'
else no 'brain: existing .git directory refused unchanged'; fi
brain_home foreign
mkdir -p -- "$CLAUDE_CONFIG_DIR/projects"
printf 'gitdir: /some/other/repository.git\n' > "$CLAUDE_CONFIG_DIR/projects/.git"
cp -- "$CLAUDE_CONFIG_DIR/projects/.git" "$tmp/original-gitfile"
if bash -- "$repo/setup.sh" --brain > "$tmp/output" 2>&1; then
  no 'brain: foreign gitfile refused unchanged'
elif cmp -s -- "$tmp/original-gitfile" "$CLAUDE_CONFIG_DIR/projects/.git" \
   && [ ! -e "$HOME/.claude" ] && [ ! -e "$XDG_STATE_HOME" ]; then
  ok 'brain: foreign gitfile refused unchanged'
else no 'brain: foreign gitfile refused unchanged'; fi

brain_home custom
# Preserve the same live keys and external hook as the upgrade fixture.
mkdir -p -- "$CLAUDE_CONFIG_DIR"
cp -- "$tmp/once.json" "$CLAUDE_CONFIG_DIR/settings.json"
setup --brain
projects="$CLAUDE_CONFIG_DIR/projects"
service="$XDG_CONFIG_HOME/systemd/user/brain-commit.service"
timer="$XDG_CONFIG_HOME/systemd/user/brain-commit.timer"
if [ -f "$projects/.git" ] \
   && [ "$(cat -- "$projects/.git")" = "gitdir: $XDG_STATE_HOME/agent-brain.git" ] \
   && [ "$(git -C "$projects" symbolic-ref --short HEAD 2>/dev/null)" = main ] \
   && [ "$(git -C "$projects" remote get-url origin 2>/dev/null)" = git@github.com:pwnjack/agent-brain.git ] \
   && [ "$(git -C "$projects" config --bool brain.enabled)" = true ] \
   && [ "$(git -C "$projects" config brain.remote)" = git@github.com:pwnjack/agent-brain.git ] \
   && [ "$(git -C "$projects" ls-tree --name-only HEAD 2>/dev/null)" = .gitignore ] \
   && [ "$(git -C "$projects" log -1 --format='%an <%ae> %cn <%ce> %s' 2>/dev/null)" = 'brain <brain@localhost> brain <brain@localhost> brain: start' ] \
   && cmp -s -- "$repo/brain/gitignore" "$projects/.gitignore" \
   && git -C "$projects" show HEAD:.gitignore > "$tmp/committed-ignore" \
   && cmp -s -- "$repo/brain/gitignore" "$tmp/committed-ignore"; then
  ok 'brain: separate git dir, main, remote, opt-in config and exact committed whitelist'
else no 'brain: separate git dir, main, remote, opt-in config and exact committed whitelist'; fi
if jq -e '.autoDreamEnabled == true and .keepMe == 1
  and any(.hooks.SessionStart[].hooks[]; .command == "bash '\''/x/herdr-agent-state.sh'\'' session")' \
  "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null \
  && jq -e 'has("autoDreamEnabled") | not' "$repo/claude/settings.json" >/dev/null; then
  ok 'brain: auto-dream enabled only in live settings; keepMe and herdr hook preserved'
else no 'brain: auto-dream enabled only in live settings; keepMe and herdr hook preserved'; fi
if [ -f "$service" ] && [ -f "$timer" ]; then
  first=$(sed -n 's/^ExecStart=//p' "$service" | jq -Rr 'capture("^(?<arg>\\\"([^\\\"\\\\]|\\\\.)*\\\") ").arg | fromjson')
  second=$(sed -n 's/^ExecStart=//p' "$service" | jq -Rr 'capture("^\\\"([^\\\"\\\\]|\\\\.)*\\\" (?<arg>.*)$").arg | fromjson')
  if [ "$first" = "$repo/brain/commit.sh" ] && [ -x "$first" ] \
     && [ "$second" = "$projects" ] && grep -qxF -- Type=oneshot "$service"; then
    ok 'brain: unit arguments name executable and custom config projects path'
  else no 'brain: unit arguments name executable and custom config projects path'; fi
  if grep -qxF -- OnStartupSec=2min "$timer" \
     && grep -qxF -- OnUnitActiveSec=30min "$timer" \
     && grep -qxF -- WantedBy=timers.target "$timer" \
     && [ "$(cat -- "$TEST_SYSTEMCTL_LOG")" = "--user daemon-reload
--user enable --now brain-commit.timer" ]; then
    ok 'brain: timer schedule installed and enabled through user systemctl'
  else no 'brain: timer schedule installed and enabled through user systemctl'; fi
  if command -v systemd-analyze >/dev/null 2>&1; then
    if systemd-analyze --user verify "$service" "$timer" > "$tmp/verify" 2>&1; then
      ok 'brain: rendered units pass systemd-analyze --user verify'
    else no 'brain: rendered units pass systemd-analyze --user verify'; cat -- "$tmp/verify"; fi
  else ok 'skip: systemd-analyze unavailable'; fi
  cp -- "$service" "$tmp/service-once"
  cp -- "$timer" "$tmp/timer-once"
  cp -- "$projects/.git" "$tmp/gitfile-once"
  cp -- "$XDG_STATE_HOME/agent-brain.git/config" "$tmp/config-once"
  cp -- "$CLAUDE_CONFIG_DIR/settings.json" "$tmp/brain-settings-once"
  head_once=$(git -C "$projects" rev-parse HEAD)
  setup --brain
  if [ "$(git -C "$projects" rev-parse HEAD)" = "$head_once" ] \
     && cmp -s -- "$service" "$tmp/service-once" \
     && cmp -s -- "$timer" "$tmp/timer-once" \
     && cmp -s -- "$projects/.git" "$tmp/gitfile-once" \
     && cmp -s -- "$XDG_STATE_HOME/agent-brain.git/config" "$tmp/config-once" \
     && cmp -s -- "$CLAUDE_CONFIG_DIR/settings.json" "$tmp/brain-settings-once"; then
    ok 'brain: second run leaves commit, gitfile, config, units and settings identical'
  else no 'brain: second run leaves commit, gitfile, config, units and settings identical'; fi
else
  no 'brain: service and timer installed'
fi

printf '# Updated whitelist from a harness upgrade.\n' >> "$repo/brain/gitignore"
head_before_refresh=$(git -C "$projects" rev-parse HEAD)
setup --brain --dry-run
if ! cmp -s -- "$repo/brain/gitignore" "$projects/.gitignore" \
   && [ "$(git -C "$projects" rev-parse HEAD)" = "$head_before_refresh" ]; then
  ok 'brain: dry run leaves an outdated whitelist and HEAD unchanged'
else no 'brain: dry run leaves an outdated whitelist and HEAD unchanged'; fi
setup --brain
if cmp -s -- "$repo/brain/gitignore" "$projects/.gitignore" \
   && [ "$(git -C "$projects" rev-parse HEAD)" = "$head_before_refresh" ] \
   && ! git -C "$projects" diff --quiet -- .gitignore \
   && git -C "$projects" diff --cached --quiet; then
  ok 'brain: repeat setup refreshes an outdated whitelist for the next memory commit'
else no 'brain: repeat setup refreshes an outdated whitelist for the next memory commit'; fi

# systemd rejects quote characters in executable names, even correctly escaped.
# Check quoting separately from verification of the normal installation above.
prepare_clone "$tmp/clone with a \"quote and a \\slash" || exit 1
brain_home quoted
setup --brain
service="$XDG_CONFIG_HOME/systemd/user/brain-commit.service"
if [ -f "$service" ]; then
  first=$(sed -n 's/^ExecStart=//p' "$service" | jq -Rr 'capture("^(?<arg>\\\"([^\\\"\\\\]|\\\\.)*\\\") ").arg | fromjson')
  if [ "$first" = "$repo/brain/commit.sh" ] && [ -x "$first" ]; then
    ok 'brain: quoted and backslashed clone path dequotes to an existing executable'
  else no 'brain: quoted and backslashed clone path dequotes to an existing executable'; fi
else no 'brain: unit installed for quoted clone path'; fi

brain_home dry-run
setup --brain --dry-run
if [ ! -e "$HOME" ] && [ ! -s "$TEST_SYSTEMCTL_LOG" ]; then
  ok 'brain: dry run creates no repository, config, units or timer'
else no 'brain: dry run creates no repository, config, units or timer'; fi

# The timer must not inherit a relative config path from the setup process.
brain_home relative
mkdir -p -- "$HOME"
(
  cd -- "$HOME" || exit 1
  export CLAUDE_CONFIG_DIR='relative config'
  setup --brain || exit 1
  service="$XDG_CONFIG_HOME/systemd/user/brain-commit.service"
  second=$(sed -n 's/^ExecStart=//p' "$service" | jq -Rr 'capture("^\\\"([^\\\"\\\\]|\\\\.)*\\\" (?<arg>.*)$").arg | fromjson')
  [ "$second" = "$HOME/relative config/projects" ]
)
if [ "$?" -eq 0 ]; then ok 'brain: relative config resolved to an absolute projects argument'
else no 'brain: relative config resolved to an absolute projects argument'; fi

# Default setup must not redirect Claude's global config to ~/.claude/.claude.json.
for mode in plain brain; do
  brain_home "unset-$mode"
  : > "$TEST_CLAUDE_CONFIG_LOG"
  if (
    unset CLAUDE_CONFIG_DIR
    if [ "$mode" = brain ]; then setup --brain; else setup; fi
  ) && [ -s "$TEST_CLAUDE_CONFIG_LOG" ] \
    && ! grep -qvxF -- UNSET "$TEST_CLAUDE_CONFIG_LOG"; then
    ok "$mode setup: every Claude invocation inherits unset CLAUDE_CONFIG_DIR"
  else no "$mode setup: every Claude invocation inherits unset CLAUDE_CONFIG_DIR"; fi
done

# Run the documented removal against links installed through a logical clone
# path, so its comparisons must use the link target rather than a physical path.
prepare_clone "$tmp/removal-clone" || exit 1
ln -s -- "$repo" "$tmp/linked-clone"
repo="$tmp/linked-clone"
brain_home removal
setup --brain
awk '
  /^## Removing the harness$/ { section = 1 }
  section && /^```bash$/ { block = 1; next }
  block && /^```$/ { exit }
  block { print }
' "$source_repo/docs/internals.md" > "$tmp/removal.sh"
if [ -s "$tmp/removal.sh" ] && bash "$tmp/removal.sh" > "$tmp/removal-output" 2>&1 \
   && [ ! -L "$HOME/.claude/harness" ] \
   && [ ! -L "$CLAUDE_CONFIG_DIR/CLAUDE.md" ] \
   && [ ! -L "$CODEX_HOME/AGENTS.md" ] \
   && [ ! -L "$CLAUDE_CONFIG_DIR/skills/delegate" ] \
   && [ ! -L "$CLAUDE_CONFIG_DIR/skills/compound-learning" ] \
   && [ -f "$CLAUDE_CONFIG_DIR/projects/.git" ] \
   && [ "$(git -C "$CLAUDE_CONFIG_DIR/projects" config --bool brain.enabled)" = false ]; then
  ok 'removal: documented commands remove logical clone links and preserve the disabled brain'
else
  no 'removal: documented commands remove logical clone links and preserve the disabled brain'
  cat -- "$tmp/removal-output"
fi

exit "$fail"
