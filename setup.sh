#!/usr/bin/env bash
# Wire the tracked AI-agent harness (claude/, codex/) into a machine.
#
# Only what this repo authored is linked or merged in; everything the agents or
# other tools write — logins, history, memory, caches, their own hooks — is
# excluded. Every step is optional: a missing claude, codex or herdr is
# skipped, never an error. Idempotent.
#
#   ./setup.sh [--dry-run] [--brain]
# --brain opts this Linux machine into private memory commits and auto-dream.
#
# Links: this repo -> ~/.claude/harness, claude/skills/*/ -> ~/.claude/skills/,
# claude/CLAUDE.global.md ->
# ~/.claude/CLAUDE.md,
# codex/AGENTS.global.md -> ~/.codex/AGENTS.md (CLAUDE_CONFIG_DIR and CODEX_HOME
# are honoured, as the apply scripts do). Anything already at a link target is
# moved — never deleted — into ~/.local/state/dotfiles-agents-backup/<time>/.
# Links into this repo whose target is gone (a removed skill or hook) are
# deleted.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dry=false
brain=false
for option in "$@"; do
  case "$option" in
    --dry-run) dry=true ;;
    --brain) brain=true ;;
    *) echo 'usage: ./setup.sh [--dry-run] [--brain]' >&2; exit 2 ;;
  esac
done
claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-agents-backup/$(date +%Y%m%d-%H%M%S)"

run() { if $dry; then echo "  would run: $*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }
refuse() { echo "agents: $*" >&2; exit 1; }

# Resolve existing ancestors without creating anything during preflight.
absolute_path() {
  local path=$1 suffix= part
  case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
  while [ ! -d "$path" ]; do
    part=$(basename -- "$path")
    suffix="/$part$suffix"
    path=$(dirname -- "$path")
  done
  printf '%s%s\n' "$(cd -- "$path" && pwd -P)" "$suffix"
}

if $brain; then
  [ "$(uname -s)" = Linux ] || refuse '--brain requires Linux'
  have gh || refuse '--brain requires gh to verify the private repository'
  visibility=$(gh repo view pwnjack/agent-brain --json visibility -q .visibility) \
    || refuse 'could not verify the brain repository visibility'
  [ "$visibility" = PRIVATE ] || refuse 'the brain repository must be PRIVATE'
fi
claude_dir=$(absolute_path "$claude_dir")
# Keep the resolved path local; do not export CLAUDE_CONFIG_DIR.

if $brain; then
  projects="$claude_dir/projects"
  brain_git=$(absolute_path "${XDG_STATE_HOME:-$HOME/.local/state}/agent-brain.git")
  units=$(absolute_path "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user")
  brain_exists=false
  if [ -e "$projects/.git" ] || [ -L "$projects/.git" ]; then
    if [ -f "$projects/.git" ] && [ ! -L "$projects/.git" ] \
       && [ "$(cat -- "$projects/.git")" = "gitdir: $brain_git" ]; then
      brain_exists=true
    else
      refuse "refusing existing repository at $projects/.git"
    fi
  fi
fi

link() {
  local src=$1 dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then return; fi
  run mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local rel=${dst#"$HOME"/} n=1
    local bak="$backup_root/${rel#/}"
    while [ -e "$bak" ] || [ -L "$bak" ]; do bak="$backup_root/${rel#/}.$n"; n=$((n + 1)); done
    echo "  moving aside existing $dst -> $bak"
    run mkdir -p "$(dirname "$bak")"
    run mv "$dst" "$bak"
  fi
  run ln -s "$src" "$dst"
  $dry || echo "  linked $dst"
}

have jq || { echo "agents: jq is required; skipping harness setup" >&2; exit 1; }
run git -C "$repo" config --local core.hooksPath githooks

# Commands in tracked settings use this fixed path even with a custom config.
link "$repo" "$HOME/.claude/harness"

if have claude; then
  echo "claude: linking harness"
  for d in "$repo"/claude/skills/*/; do
    d=${d%/}; link "$d" "$claude_dir/skills/$(basename "$d")"
  done
  for l in "$claude_dir"/skills/* "$claude_dir"/hooks/*; do
    if [ -L "$l" ] && [ ! -e "$l" ] && [[ $(readlink "$l") == "$repo"/claude/* ]]; then
      echo "  removing stale link $l"; run rm "$l"
    fi
  done
  link "$repo/claude/CLAUDE.global.md" "$claude_dir/CLAUDE.md"
  run bash "$repo/claude/apply-settings.sh"

  # Plugins named in the tracked settings: add their marketplaces, then install.
  # Listing them initializes Claude's own state, so a dry run skips the query
  # and shows every step as it would run on a fresh machine.
  have_mkt=
  $dry || have_mkt=$(claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name' || true)
  while IFS=$'\t' read -r name src; do
    grep -qxF -- "$name" <<<"$have_mkt" || run claude plugin marketplace add "$src"
  done < <(jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
                  | [.key, (.value.source | .repo // .url)] | @tsv' "$repo/claude/settings.json")
  have_plug=
  $dry || have_plug=$(claude plugin list --json 2>/dev/null | jq -r '.[].id' || true)
  while read -r plugin; do
    grep -qxF -- "$plugin" <<<"$have_plug" || run claude plugin install "$plugin" --scope user
  done < <(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$repo/claude/settings.json")
else
  echo "claude: not installed, skipping"
fi

if have codex; then
  echo "codex: linking harness"
  link "$repo/codex/AGENTS.global.md" "$codex_dir/AGENTS.md"
  run bash "$repo/codex/apply-config.sh"
  run bash "$repo/codex/apply-hooks.sh"
else
  echo "codex: not installed, skipping"
fi

# Merge the sidebar layout, then install agent-state hooks through Herdr.
if have herdr; then
  run bash "$repo/herdr/apply-config.sh"
  for agent in claude codex; do
    have "$agent" || continue
    if ! $dry && herdr integration status 2>/dev/null | grep -q "^$agent: current"; then continue; fi
    run herdr integration install "$agent"
  done
fi

if $brain; then
  if ! $brain_exists; then
    run mkdir -p -- "$projects" "$(dirname -- "$brain_git")"
    run git init -b main --separate-git-dir "$brain_git" -- "$projects"
    run git -C "$projects" remote add origin git@github.com:pwnjack/agent-brain.git
    run git -C "$projects" config --local brain.enabled true
    run git -C "$projects" config --local brain.remote git@github.com:pwnjack/agent-brain.git
    run cp -- "$repo/brain/gitignore" "$projects/.gitignore"
    run git -C "$projects" add -- .gitignore
    GIT_AUTHOR_NAME=brain GIT_AUTHOR_EMAIL=brain@localhost \
    GIT_COMMITTER_NAME=brain GIT_COMMITTER_EMAIL=brain@localhost \
      run git -C "$projects" -c commit.gpgsign=false -c core.hooksPath=/dev/null \
        commit -m 'brain: start'
  elif ! cmp -s -- "$repo/brain/gitignore" "$projects/.gitignore"; then
    # The next scanned memory commit records whitelist upgrades too.
    run cp -- "$repo/brain/gitignore" "$projects/.gitignore"
  fi

  run mkdir -p -- "$units"
  if $dry; then
    echo "  would render: $units/brain-commit.service"
    echo "  would enable autoDreamEnabled in $claude_dir/settings.json"
  else
    # JSON quoting supplies systemd's double-quoted argument syntax. Escape
    # specifiers and environment expansion too, so paths remain literal.
    jq -Rrs --arg command "$repo/brain/commit.sh" --arg projects "$projects" '
      def argument: gsub("%"; "%%") | gsub("\\$"; "$$") | tojson;
      gsub("@(?<name>COMMAND|PROJECTS)@";
        if .name == "COMMAND" then $command | argument
        else $projects | argument end)
    ' "$repo/brain/brain-commit.service.in" > "$units/brain-commit.service"
  fi
  run cp -- "$repo/brain/brain-commit.timer" "$units/brain-commit.timer"
  run systemctl --user daemon-reload
  run systemctl --user enable --now brain-commit.timer
  if ! $dry; then
    settings="$claude_dir/settings.json"
    [ -s "$settings" ] || printf '{}\n' > "$settings"
    settings_tmp=$(mktemp "$settings.XXXXXX")
    trap 'rm -f -- "$settings_tmp"' EXIT
    cp -p -- "$settings" "$settings_tmp"
    jq '.autoDreamEnabled = true' "$settings" > "$settings_tmp"
    if ! cmp -s -- "$settings" "$settings_tmp"; then
      mv -- "$settings_tmp" "$settings"
    fi
    rm -f -- "$settings_tmp"
    trap - EXIT
  fi
fi
