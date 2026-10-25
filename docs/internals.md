# Agent harness internals

Read this before changing anything under `claude/`, `codex/` or `brain/`.
The files agents load every session stay short on purpose; the reasons and
the measured traps live here.

## Files

| Tracked | Live location | How |
|---|---|---|
| repository root | `~/.claude/harness` | symlink to the clone |
| `claude/CLAUDE.global.md` | `~/.claude/CLAUDE.md` | symlink |
| `claude/skills/*/` | `~/.claude/skills/*` | symlinks, including `delegate` and `compound-learning` |
| `claude/hooks/agent-guard.sh` | named in the settings | run in place |
| `claude/hooks/advisor-reset.sh` | named in the settings | run in place at non-worker startup |
| `claude/settings.json` | `~/.claude/settings.json` | merged by `claude/apply-settings.sh` |
| `claude/statusline.sh` | named in the settings | run in place |
| `codex/AGENTS.global.md` | `~/.codex/AGENTS.md` | symlink |
| `codex/*.toml` | `~/.codex/config.toml` | merged by `codex/apply-config.sh` |
| `brain/gitignore` | `<config>/projects/.gitignore` | exact copy, committed in the brain |
| `brain/brain-commit.service.in`, `brain/brain-commit.timer` | `~/.config/systemd/user/brain-commit.{service,timer}` | rendered service and copied timer, with `--brain` |

The public harness is `git@github.com:pwnjack/agent-harness.git`, normally
cloned at `~/Developer/agent-harness`. `./setup.sh [--dry-run] [--brain]`
does the wiring, skips any tool that is absent, moves
an existing file aside instead of deleting it (into
`~/.local/state/dotfiles-agents-backup/<time>/`, outside the directories the
agents scan), deletes links into this repo whose target is gone, and has Herdr
install its own agent-state hooks for each tool that is present. It also sets
the clone's `core.hooksPath` to `githooks`. The global
files are not named `CLAUDE.md`/`AGENTS.md` so that neither loads as a nested
project file. Neither live settings file can be a symlink, because the tools
write to them. Edit the tracked file, then run the apply script.

`<config>` means `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, resolved once to an
absolute path by setup; later brain processes receive that path as an argument.
The table shows default locations: Claude links and settings follow `<config>`,
Codex follows `${CODEX_HOME:-$HOME/.codex}`, and state and units follow
`XDG_STATE_HOME` and `XDG_CONFIG_HOME`. The harness link is always
`$HOME/.claude/harness`, even with a custom `<config>`, because tracked commands
name that path literally. Setup never exports `CLAUDE_CONFIG_DIR`: doing so
would make Claude read `~/.claude/.claude.json` instead of `~/.claude.json`.

The tracked `claude/settings.json` also carries a `permissions.deny` list that
keeps agents out of the secrets (`.env` files, `~/.ssh`, `~/.gnupg`, the
calendar and vdirsyncer data), the Agent-tool guard hook, the status line
command and the plugin list. `codex/statusline.toml` is the tracked slice of
Codex's `config.toml`.

`codex/features.toml` pins `memories = false` under `[features]`; Codex does
not capture a second memory store through that feature.

Never tracked: logins, history, memory, caches, plugin checkouts, and anything
a tool writes into its own config (Herdr's agent-state hooks, project trust,
auto-mode text). The repo is public and a fresh machine stays fresh.

## Context budget

Everything in `CLAUDE.global.md`, `AGENTS.global.md`, the project `CLAUDE.md`,
the memory index, and each enabled plugin's skill listing and session hooks is
paid for on every session and every worker. Before adding a line there, ask
whether an agent needs it on every task; if it needs it only for one kind of
task, it belongs in a skill or in this directory.

`test-budgets.sh` caps the two global files at their recorded byte budgets
and checks tracked shell scripts for non-portable flags. Six older files are
explicitly exempt from that portability check; new scripts target Bash 3.2
and jq.

## Brain

The brain is the private `git@github.com:pwnjack/agent-brain.git` repository.
Its worktree is `<config>/projects`, where Claude already writes memory; its
git directory is `~/.local/state/agent-brain.git` (or under `XDG_STATE_HOME`).
The public harness contains only the scripts, patterns, whitelist and unit
templates. Memory never belongs in the public repository.

`./setup.sh --brain` is opt-in and Linux-only. Before changing anything it
requires `gh repo view pwnjack/agent-brain --json visibility -q .visibility`
to report `PRIVATE`. It uses `git init -b main --separate-git-dir`, sets
`origin`, `brain.remote` and `brain.enabled=true`, and commits the exact
`brain/gitignore` as `brain: start`. An existing matching gitfile is reused;
a foreign `.git`, including a directory, is refused. A completed installation
can be run again without changing its history or settings. If the tracked
whitelist has changed, `--brain` refreshes `<config>/projects/.gitignore`;
the next memory commit records it. Plain setup
does not create a brain or enable auto-dream.

The whitelist admits only `.gitignore` and non-hidden Markdown files beneath
`*/memory/`, including subdirectories. It excludes `-tmp*` projects, hidden
paths within memory, session JSONL, caches and other project data. Keep the
installed `.gitignore` byte-identical to `brain/gitignore`: the commit script
refuses a missing or altered copy, and refuses any tracked ignored file.

The rendered service runs `brain/commit.sh <projects-dir>`. The timer starts
two minutes after login (`OnStartupSec=2min`) and then every thirty minutes
(`OnUnitActiveSec=30min`). Units live in `~/.config/systemd/user/` (or under
`XDG_CONFIG_HOME`); they are generated machine files, ignored by the dotfiles
whitelist, and must never be tracked there. Inspect runs with:

```bash
systemctl --user status brain-commit.timer
journalctl --user -u brain-commit
```

The commit script builds its candidate tree in a temporary index, ignoring
unrelated staging. It independently validates every candidate path against
the whitelist, so nested `.gitignore` files cannot admit other files.
After publishing a commit it resets the shared index to the new tree,
discarding unrelated staging while leaving worktree files untouched. A failed
index synchronisation is logged without undoing the commit.
It scans the whole candidate tree with `git grep --cached` and the named
patterns in `brain/patterns`; a match refuses the commit and reports the path
and pattern name, never the secret value. Commits use `brain <brain@localhost>`
for author and committer and name the changed project keys. If the branch
moves during the run, it exits successfully and retries next time. An update
failure with an unchanged branch logs Git's error and exits unsuccessfully.
It requires `main` and refuses to push unless every push URL is exactly
`brain.remote`.
`ssh-add -l` returning 1 or 2 defers the push; commits stay local until a key
is available. Pushes have a 60-second timeout, `GIT_TERMINAL_PROMPT=0` and
`GIT_SSH_COMMAND='ssh -o BatchMode=yes'`. A failed push logs the last ten lines
of Git's output and retries on the next run.

`brain/audit.sh <projects-dir> [project-key...]` is read-only. It reports
Markdown memories absent from `MEMORY.md`, index links to missing files and
secret patterns by name. A `MEMORY.md` over 4096 bytes is a warning. The commit
script journals the audit after a new commit; an audit warning or error does
not undo that commit.

`--brain` enables `autoDreamEnabled` in the live Claude settings only. To stop
automatic commits, run `systemctl --user disable --now brain-commit.timer`.
To make even a manual invocation of the commit script a no-op, run
`git -C <config>/projects config brain.enabled false`. To stop auto-dream,
delete `autoDreamEnabled` from the live settings as shown under removal below.
These switches are independent and preserve the repository and its history.

The `compound-learning` skill turns an evidenced correction into one lasting
prevention: a check, project documentation, skill, global instruction or
memory, in that order. It runs only in the main checkout's orchestrator;
workers and worktree sessions report lessons instead. It audits memory before
searching existing guidance, strips private details from public proposals and
requires a diff proposal and the user's yes for harness changes, followed by
review in a worktree before merging. Its injection guard covers the skill
only: Claude's native memory capture and auto-dream bypass it, and the audit
does not establish provenance.

Deferred:

- A shared `skills/` directory used by both agents.
- Capture of lessons on the Codex side.
- A cross-family review of each auto-dream diff.
- A private cross-project lessons file imported by the global `CLAUDE.md`.
- A report tool or dashboards.
- The macOS port of the six files on the portability exemption list.

## Advisor

The advisor is unset by default. `claude/apply-settings.sh` deletes
`advisorModel` on every merge. The `SessionStart` hook with matcher `startup`
runs `claude/hooks/advisor-reset.sh`, which clears `advisorModel` whenever any
non-worker Claude session starts, including a scripted `claude -p`. Claude
watches `settings.json`, so a running session can lose the advisor at that
moment: enable `/advisor fable` only in the one session doing the work.

Claude workers launched by `pane.sh` always get
`CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` and `HARNESS_LEAF=1` through `--settings`
`env`. The first disables their advisor tool; the second makes their reset
hook leave the user's live advisor choice alone. The same settings argument
disables Superpowers for workers. Advisor use remains the user's choice;
global instructions ask the orchestrator to propose it with a reason.

## Delegation design

- **Cross-family review.** Claude's work is reviewed by Codex and Codex's by
  Claude, because a model reviewing its own family shares its blind spots. With
  no usable Codex the fallback is a different Claude tier in a fresh context,
  which is weaker and is reported as such.
- **Blind review.** A reviewer told what the implementer worried about finds
  that and stops looking. Disagreement between a blind review and the
  implementer's self-report is the most useful output, so the reviewer never
  sees the report.
- **One review mandate.** Only `CLAUDE.global.md` requires a review. Earlier
  versions had four separate mandates (global file, routing skill, implement
  skill, Superpowers) and needed a diff-hash cache to stop them stacking; the
  cache and the extra mandates are gone.
- **Every worker runs in a Herdr pane**, Claude and Codex alike, so the user
  can watch it work (the user's call, 2026-10-13). `pane.sh` spawns, prompts and
  waits in one background call. The first worker splits the orchestrator's
  pane to the right, later ones stack below the newest worker, and each opens
  in the caller's directory, so an SDD worktree is the worker's project root
  and sandbox. The Agent tool is only the Claude fallback outside Herdr; it
  honours `model` (Haiku verified as Haiku, 2026-10-13).
- **Superpowers dispatches are roles.** Its skills name the Agent tool for
  every implementer and reviewer; the `delegate` skill maps each one onto a
  pane, picks its model from the same table, and keeps every reviewer
  cross-family and blind, SDD's per-task reviewer included (its template
  otherwise reads the implementer's report). `pane.sh` with `DELEGATE_KEEP=1`
  keeps an implementer's pane open so SDD's fix rounds resume it, and
  `pane.sh --resume` sends each round with a fresh report path. Briefs come
  from `sdd-brief.sh`, which fills the plugin's own templates and fails
  closed when they change: a hand-edited brief once named an empty diff
  range. It splices values in Python as literal text; an earlier sed version
  ran a crafted plan title as a GNU sed `e` command. The
  Herdr-only `claude/hooks/agent-guard.sh` refuses the Agent tool, so the
  plugin's wording cannot route around the panes; outside Herdr it is silent.
- **Recursion guards.** A Claude pane gets a leaf directive through
  `--append-system-prompt`; the brief's `[LEAF WORKER — DO NOT DELEGATE]` line
  and the leaf rule in `CLAUDE.global.md` back it up, and are the only guard on
  the Agent-tool fallback. Codex's `AGENTS.md` makes it a leaf whenever a report
  path or the marker is present.
- **The report contract travels in the prompt.** `pane.sh` names the report
  path and its JSON keys in the one-line prompt, so it holds for Claude, which
  has no `AGENTS.md` report section. It also checks the shape: 4 of the first
  28 reports broke it (`concerns` as one string, `tests_run` as an object), so
  a malformed report is `NOREPORT` and is moved aside for a fresh one.
- **Model names.** Skills name aliases (`sonnet`) and Codex codenames (`sol`),
  never pinned IDs, so they survive new generations; `test-skills.sh` enforces
  this. `codex-model.sh` resolves a codename to the newest listed model of that
  name at launch (its header is the full rule) and clamps the effort to what
  the model lists.
- **Model and effort are chosen together** (the user's rule, 2026-10-13). A
  lighter model is already a saving, so it is never paired with low effort:
  the skill's table gives each kind of work one model-and-effort pair per
  family, and `low` is not used for delegated work. Effort is raised while a
  task is within a model's reach; past that, the model moves up. Both families
  implement and review from the same table. Codex `terra` is off the table (it
  has no current generation, and `luna` covers light work) but still runs by
  name.
- **Opt-in models are an allow-list.** Only Claude `haiku`, `sonnet`, `opus`
  (`CLAUDE_STANDARD` in `pane.sh`) and Codex `luna`, `terra`, `sol` (`STANDARD`
  in `codex-model.sh`) run freely. Every other name, `fable`, `astra` and
  anything shipped later, needs `DELEGATE_EXPENSIVE=1`, set only when the user
  asked. That includes a model Codex `inherit` or the degrade path would launch
  through `config.toml` (read from `CODEX_HOME`, then pinned with `-m` so the
  model checked is the one that runs), and a launch whose model cannot be
  determined. A new version of a standard model needs no edit; a new name stays
  gated until it is deliberately added. The earlier deny-list needed a hand
  edit for every new flagship and failed open until then.
- **Effort** is `low`, `medium`, `high` or `xhigh` for both families (Claude
  through `--effort`, Codex through `model_reasoning_effort`). `max` is never
  used, and Codex `ultra` turns on its own delegation. Codex effort is clamped
  to what the resolved model lists.

## Measured traps

- `codex login status` passes with the quota exhausted, and once with every
  request failing "model is not supported when using Codex with a ChatGPT
  account". The `QUOTA` verdict is the only reliable signal, so it is not
  probed up front.
- Codex can open a "hooks need review" screen that swallows the first prompt
  while Herdr reports `working`. `pane.sh` looks for it, sends Escape and
  resends once. Never answer it with "trust all"; that is the user's call.
- Quota is checked only once the worker is idle, against Codex's own error
  wording at the bottom of the screen. Matching any "quota" text, or checking
  while blocked, flagged tasks that merely talked about limits as quota hits
  and turned Codex off for the session.
- `--wait` keeps the pane by default (`DELEGATE_KEEP=0` closes it on REPORT):
  an earlier `--wait` closed a reviewer's pane after its report and lost a
  long session's context (2026-10-25).
- A first-run folder-trust prompt makes `herdr agent start` fail
  (`agent_not_ready`). `pane.sh` then returns BLOCKED and keeps the pane so
  the prompt can be answered; the brief was never sent, so close the pane and
  rerun. Closing it on that failure made the prompt unanswerable three times
  in a row (2026-10-25).
- After `--wait`, the question just answered can still read as `blocked` for a
  moment, so a block in the first seconds of a resumed wait is not reported.
- Herdr agent names match `^[a-z][a-z0-9_-]{0,31}$` (no spaces, dots or
  capitals); anything else fails with `invalid_agent_name` and leaves an empty
  pane. `pane.sh` names each pane `<role>-<model>-<task>`, refuses one that
  would not fit, and finds the delegate column by the role prefix. The older
  `dlg-<kind>-<slug>` read `dlg-claude-dlg-impl-privacy` in the sidebar,
  because callers repeated the prefix and the kind in the slug and the model
  was missing.
- Herdr's `done` can mean the turn ended while the TUI is still up; it is
  treated like `idle`.
- Headless `codex exec` waits for stdin forever unless given `< /dev/null` (or
  the prompt on stdin), so wrap it in a timeout.
- Codex ignores `plugins."<id>".enabled` for a remote plugin, in
  `config.toml` and through `-c` alike: `google-drive` set to `false` still
  loaded in a pane worker (2026-10-13). `codex exec` loads no remote plugins at
  all, so only a real pane shows what a worker sees.
- A pane worker's history is not in Herdr (`herdr agent read --source
  scrollback` came back empty); a Codex worker's commands and token totals are
  in its session log under `~/.codex/sessions/<date>/`.
- `claude/apply-settings.sh` merges objects key by key, and a tracked hook
  group replaces live hooks that run the same script file. It drops a live hook
  whose `~/.claude/hooks` script is gone, but otherwise never removes a key: a
  setting dropped from the tracked file must also be removed from the live file
  by hand. `advisorModel` is the deliberate exception: every merge deletes it.

## Plugins

- **impeccable** (UI design) is registered but off. Its hooks run on every
  edit and every turn end. Turn it on for design work with
  `claude plugin enable impeccable@impeccable`, and off again afterwards.
- **Superpowers** drives the development workflow: brainstorm, spec, plan,
  test first, review, verify. Claude only: it is enabled in the tracked
  settings and `setup.sh` installs it. Claude pane workers start with it off
  (`pane.sh`): a leaf that brainstorms waits for an approval no one gives, and
  its session text would fill every worker. It is not installed on Codex
  (removed 2026-10-13): Codex is a worker and reviewer here, the SDD briefs
  already carry the test-first steps, and a Codex implementer with it spent
  4 of 18 commands and about 13 KB of context re-reading skill files.
  Reinstall with `codex plugin add superpowers@openai-curated-remote` only to
  lead from Codex. Its plans and specs in `docs/superpowers/` stay local and
  untracked.
- **mgrep** was removed on 2026-10-13. Its session hook told agents never to
  use Grep or WebSearch, contradicting the `rg` guidance, and it uploaded every
  project to Mixedbread. `rg` and an Explore agent cover this repo.
- **Upgrading a machine set up before 2026-10-13:** `setup.sh` removes the old
  skill and hook links and the hook entry, but not plugins it used to install.
  The `superpowers-extended-cc` fork is not the Superpowers above. Run
  `claude plugin uninstall superpowers-extended-cc@superpowers-extended-cc-marketplace`
  and `claude plugin uninstall mgrep@Mixedbread-Grep` (then
  `claude plugin marketplace remove` for each marketplace), and
  `codex mcp remove mgrep`.
- **Codex:** the ECC plugin (281 skills, a session bootstrap and an MCP server
  in every Codex session, workers included) and the mgrep MCP server were
  turned off in `~/.codex/config.toml`. That is machine state, not tracked.

## Status lines

`claude/statusline.sh` prints the model and effort, the context as a one-cell
pie with token counts, and the 5-hour and 7-day limits as FiraCode progress
bars with their reset times (12 h or 24 h, following `options/clock`). Codex
shows the equivalent fields from `codex/statusline.toml`.

## Removing the harness

For a machine installed with `--brain`, run the following in Bash, in order.
Use the same config and XDG paths as at installation; the defaults below need
no exports. With no brain installed, omit the timer, units and brain config
commands. Stop active Claude sessions while editing the settings so they do
not write them back. Keep the clone available until the settings and links
have been removed.

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
rules and `autoDreamEnabled`. Other hooks, including Herdr's, survive even
when they share a group with a removed hook; unrelated settings and deny rules
survive too. Only skill and instruction symlinks pointing at this clone are
removed. The brain worktree, its `.git` file and the separate git directory
remain, with automatic commits disabled.

Ordinary merged preferences, plugin registrations and installed plugins stay
in place, as do Codex's TOML settings, including `memories = false`. Review
those separately against `claude/settings.json` and `codex/*.toml` if reverting
preferences too. The clone's `core.hooksPath=githooks` remains local to that
clone; the removal does not alter other repositories or restore old backups.

## Tests

- `test-setup.sh`: upgrades and fresh installs, fixed harness link with custom
  config paths, settings preservation, dry runs, private Linux-only brain
  setup, refusal of foreign repositories, rendered units and repeat runs.
- `test-budgets.sh`: byte budgets for global instructions and portable flags
  outside the explicit exemption list.
- `brain/test-audit.sh`: memory index links, ordering, secret diagnostics,
  nested paths, excluded files and the 4096-byte warning.
- `brain/test-commit.sh`: whitelist and secret refusals, shared index
  synchronisation, stale locks and concurrent updates, symlinked project
  paths, commit identity, push URL checks, SSH deferral and push diagnostics
  and retries.
- `claude/skills/test-skills.sh`: frontmatter, referenced files, no pinned
  IDs, plugin marketplaces.
- `claude/skills/delegate/test-delegate.sh`: model resolution, the opt-in gate,
  and every `pane.sh` verdict against a stub `herdr`, including the
  hook-review recovery (one Escape, one resend), limit text that is not a quota
  hit, a malformed report (NOREPORT, moved aside), a resumed `--wait`, `DELEGATE_KEEP`, `--resume`, and the Claude
  worker settings argument disabling Superpowers and the advisor, with
  `HARNESS_LEAF=1`.
- `claude/skills/delegate/test-sdd-brief.sh`: every brief kind is filled and
  blind, bad ranges and changed templates are refused, hostile titles and file
  names stay literal data; against stand-in templates and scripts (no plugin
  needed) and, when installed, the plugin's own.
- `claude/hooks/test-agent-guard.sh`: the guard denies inside Herdr, is silent
  outside it, and is registered once even after two settings merges.
- `claude/hooks/test-advisor-reset.sh`: startup registration, removal of
  `advisorModel`, worker bypass, settings mode and malformed settings.
- `codex/test-codex-config.sh`: `memories = false`, preservation of unrelated
  settings and repeat merges.

All ten run under `./test.sh`; `./test.sh --list` lists the discovered suites.
The pre-commit gate runs them against a private export of the staged tree.
Tests use a temporary HOME, config and state directories and stub machine
commands, including Herdr, so they never install hooks or units on the host.
