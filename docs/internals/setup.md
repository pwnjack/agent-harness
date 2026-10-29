# Setup, settings and removal

## Files

| Tracked | Live location | How |
|---|---|---|
| repository root | `~/.claude/harness` | symlink to the clone |
| `claude/CLAUDE.global.md` | `~/.claude/CLAUDE.md` | symlink |
| `claude/skills/*/` | `~/.claude/skills/*` | symlinks |
| `claude/hooks/agent-guard.sh` | named in the settings | run in place |
| `claude/hooks/advisor-reset.sh` | named in the settings | run in place at non-worker startup |
| `claude/settings.json` | `~/.claude/settings.json` | merged by `claude/apply-settings.sh` |
| `claude/statusline.sh` | named in the settings | run in place |
| `codex/AGENTS.global.md` | `~/.codex/AGENTS.md` | symlink |
| `codex/*.toml` | `~/.codex/config.toml` | merged by `codex/apply-config.sh` through `lib/toml-merge.sh` |
| `brain/gitignore` | `<config>/projects/.gitignore` | exact copy, committed in the brain |
| `brain/brain-commit.service.in`, `brain/brain-commit.timer` | `~/.config/systemd/user/` | rendered with `--brain` |

`./setup.sh [--dry-run] [--brain]` does the wiring. It skips any absent tool,
moves an existing file aside into `~/.local/state/dotfiles-agents-backup/<time>/`
instead of deleting it, deletes links into this repo whose target is gone,
lets Herdr install its own agent-state hooks, and sets the clone's
`core.hooksPath` to `githooks`.

- The global files are named `CLAUDE.global.md` and `AGENTS.global.md`.
- Live settings are regular files. Edit the tracked file, then run the apply
  script.
- `<config>` is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, resolved once by setup
  and passed to later processes as an argument. Codex follows
  `${CODEX_HOME:-$HOME/.codex}`; state and units follow `XDG_STATE_HOME` and
  `XDG_CONFIG_HOME`.
- The harness link is always `$HOME/.claude/harness`.
- Setup never exports `CLAUDE_CONFIG_DIR`; `test-setup.sh` checks this.
- `claude/apply-settings.sh` merges objects key by key and replaces a live
  hook that runs the same script file. It drops a live hook whose
  `~/.claude/hooks` script is gone but otherwise never removes a key, so a
  setting dropped from the tracked file must be removed from the live file by
  hand. It always deletes `advisorModel`.

The tracked `claude/settings.json` carries the `permissions.deny` list that
keeps agents out of secrets (`.env` files, `~/.ssh`, `~/.gnupg`, calendar and
vdirsyncer data), the Agent-tool guard hook, the advisor-reset hook, the
status line and the plugin list. `codex/statusline.toml` is the tracked slice
of Codex's `config.toml`; `codex/features.toml` sets `memories = false`.

Never track logins, history, memory, caches, plugin checkouts, or anything a
tool writes into its own config (Herdr's hooks, project trust, auto-mode
text).

## Context budget

Add text to `CLAUDE.global.md`, `AGENTS.global.md`, a project `CLAUDE.md`,
the memory index, or an enabled plugin's skill listing and session hooks only
if every task needs it; otherwise put it in a skill or in `docs/internals/`.
Tracked files are a manual for the agent: they describe what exists and how
to use it. Decisions, lessons, traps and history go to memory.

`test-budgets.sh` caps both global files at their recorded byte budgets,
fails on dated history in tracked Markdown, and checks shell scripts for
non-portable flags. The six files in `EXEMPT` skip the portability check;
new scripts target Bash 3.2 and jq.

## Plugins

Superpowers is the only plugin: listed in the tracked settings and installed
by `setup.sh`. `pane.sh` starts Claude workers without it. Its plans and specs
in `docs/superpowers/` stay local and untracked.

## Status lines

`claude/statusline.sh` prints the model and effort, the context as a one-cell
pie with token counts, and the 5-hour and 7-day limits as FiraCode progress
bars with their reset times (12 h or 24 h, following `options/clock` when the
dotfiles provide it). Codex shows the same fields from `codex/statusline.toml`.

## Removing the harness

For a machine installed with `--brain`, save the block below as a file and run
it with `bash`, in order (it does not paste into fish). Use the same config
and XDG paths as at installation; the defaults need no exports. Without a
brain, omit the timer, unit and brain config commands. Stop active Claude
sessions first so they do not write the settings back, and keep the clone in
place until the settings and links are removed.

```bash
(
set -euo pipefail
config=$(cd -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" && pwd -P)
codex_dir=${CODEX_HOME:-$HOME/.codex}
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
harness=$(readlink "$HOME/.claude/harness")
settings="$config/settings.json"

systemctl --user disable --now brain-commit.timer
rm -- "$units/brain-commit.service" "$units/brain-commit.timer"
systemctl --user daemon-reload
git -C "$config/projects" config brain.enabled false

settings_tmp=$(mktemp "$settings.XXXXXX")
trap 'rm -f -- "$settings_tmp"' EXIT
cp -p -- "$settings" "$settings_tmp"
jq --slurpfile tracked "$harness/claude/settings.json" '
  $tracked[0] as $ours
  | (if .statusLine == $ours.statusLine then del(.statusLine) else . end)
  | reduce ["SessionStart", "PreToolUse"][] as $event (.;
      ([$ours.hooks[$event][].hooks[].command]) as $commands
      | if .hooks[$event] != null then
          .hooks[$event] |= [ .[]
            | .hooks |= map(select(.command as $command
                | ($commands | index($command)) == null))
            | select(.hooks | length > 0) ]
          | if (.hooks[$event] | length) == 0
            then del(.hooks[$event]) else . end
        else . end)
  | if .permissions.deny != null then
      .permissions.deny -= $ours.permissions.deny
      | if (.permissions.deny | length) == 0
        then del(.permissions.deny) else . end
    else . end
  | del(.autoDreamEnabled)
' "$settings" > "$settings_tmp"
mv -- "$settings_tmp" "$settings"

rm -- "$HOME/.claude/harness"
for skill in "$harness"/claude/skills/*/; do
  skill=${skill%/}
  link="$config/skills/${skill##*/}"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$skill" ]; then
    rm -- "$link"
  fi
done
if [ -L "$config/CLAUDE.md" ] \
   && [ "$(readlink "$config/CLAUDE.md")" = "$harness/claude/CLAUDE.global.md" ]; then
  rm -- "$config/CLAUDE.md"
fi
if [ -L "$codex_dir/AGENTS.md" ] \
   && [ "$(readlink "$codex_dir/AGENTS.md")" = "$harness/codex/AGENTS.global.md" ]; then
  rm -- "$codex_dir/AGENTS.md"
fi
)
```

The jq filter removes the tracked status line only if it still matches, the
guard and advisor-reset commands from their hook groups, the tracked deny
rules and `autoDreamEnabled`. Other hooks, including Herdr's, and unrelated
settings survive. Only skill and instruction symlinks pointing at this clone
are removed. The brain worktree, its `.git` file and its git directory remain,
with automatic commits disabled. Merged preferences, plugin registrations,
installed plugins and Codex's TOML settings stay; review them against
`claude/settings.json` and `codex/*.toml` to revert those too. The clone's
`core.hooksPath` stays local to that clone.
