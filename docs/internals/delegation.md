# Delegation, models and advisor

## Design

- **Cross-family review.** Claude's work is reviewed by Codex and Codex's by
  Claude, because a model reviewing its own family shares its blind spots.
  With no usable Codex, a different Claude tier in a fresh context reviews,
  which is weaker and is reported as such.
- **Blind review.** The reviewer never sees the implementer's report: told
  what the implementer worried about, it finds that and stops looking.
- **One review mandate.** Only `CLAUDE.global.md` requires a review; adding
  mandates elsewhere makes them stack.
- **Every worker runs in a Herdr pane**, Claude and Codex alike, so the user
  can watch it. `pane.sh` spawns, prompts and waits in one background call.
  The first worker splits the orchestrator's pane to the right, later ones
  stack below the newest worker, and each opens in the caller's directory, so
  an SDD worktree is the worker's project root and sandbox. The Agent tool is
  only the Claude fallback outside Herdr; it honours `model`.
- **Superpowers dispatches are roles.** The `delegate` skill maps each
  implementer and reviewer onto a pane, picks its model from the same table,
  and keeps every reviewer cross-family and blind, SDD's per-task reviewer
  included. `DELEGATE_KEEP=1` on launch keeps an implementer's pane for fix
  rounds; `--resume` sends each round with a fresh report path. Briefs come
  only from `sdd-brief.sh`, which fills the plugin's own templates, splices
  values in Python as literal text, and fails closed when a template changes.
  The Herdr-only `claude/hooks/agent-guard.sh` refuses the Agent tool, so the
  plugin's wording cannot route around the panes; outside Herdr it is silent.
- **Recursion guards.** A Claude pane gets a leaf directive through
  `--append-system-prompt`; the brief's `[LEAF WORKER — DO NOT DELEGATE]` line
  and the leaf rule in `CLAUDE.global.md` back it up and are the only guard on
  the Agent-tool fallback. Codex's `AGENTS.md` makes it a leaf whenever a
  report path or the marker is present. A leaf never starts agents, so live
  checks that need a Claude or Codex session belong to the orchestrator.
- **Report contract.** `pane.sh` names the report path and its JSON keys in
  the prompt, so the contract holds for Claude too. Workers often break the
  shape, so a malformed report is `NOREPORT` and is moved aside for a fresh
  one.
- **Model names.** Skills name aliases (`sonnet`) and Codex codenames (`sol`),
  never pinned IDs; `test-skills.sh` enforces this. `codex-model.sh` resolves
  a codename to the newest listed model of that name at launch and clamps the
  effort to what the model lists.
- **Model and effort are one decision.** A lighter model is already a saving,
  so it is never paired with low effort: the skill's table gives each kind of
  work one model-and-effort pair per family, and `low` is not used for
  delegated work. Raise effort while a task is within a model's reach; past
  that, move up a model. Codex `terra` is off the table but still runs by name.
- **Opt-in models are an allow-list.** Only Claude `haiku`, `sonnet`, `opus`
  (`CLAUDE_STANDARD` in `pane.sh`) and Codex `luna`, `terra`, `sol`
  (`STANDARD` in `codex-model.sh`) run freely. Every other name, `fable`,
  `astra` and anything new, needs `DELEGATE_EXPENSIVE=1`, set only when the
  user asked. That covers a model Codex `inherit` or the degrade path would
  launch through `config.toml` (pinned with `-m` so the checked model runs)
  and a launch whose model cannot be determined.
- **Effort** is `low`, `medium`, `high` or `xhigh` for both families. Never
  `max`; never Codex `ultra`, which turns on its own delegation.

## Advisor

The advisor bills usage credits, so it is unset by default.
`claude/apply-settings.sh` deletes `advisorModel` on every merge, and
`claude/hooks/advisor-reset.sh` (`SessionStart`, matcher `startup`) clears it
whenever a non-worker Claude session starts, including a scripted
`claude -p`. Claude watches `settings.json`, so a running session can lose
the advisor at that moment: enable `/advisor fable` only in the one session
doing the work. The orchestrator proposes it with a reason; the user decides.

Claude workers launched by `pane.sh` get `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`
and `HARNESS_LEAF=1` through the `--settings` `env` object, which also turns
Superpowers off. The first disables their advisor tool; the second makes the
reset hook leave the user's choice alone.

## Herdr and Codex behaviour

- `codex login status` passes with the quota exhausted or with every request
  failing, so it is not probed; the `QUOTA` verdict is the only reliable
  signal.
- Codex can open a "hooks need review" screen that swallows the first prompt
  while Herdr reports `working`. `pane.sh` sends Escape and resends once.
  Never answer it with "trust all"; that is the user's call.
- Check quota only when the worker is idle, against Codex's own error wording
  at the bottom of the screen; matching any "quota" text misfires on tasks
  that discuss limits.
- `--wait` and `--resume` keep the pane on REPORT; `DELEGATE_KEEP=0` makes
  `--wait` close it. QUOTA always closes it.
- A first-run folder-trust prompt makes `herdr agent start` fail with
  `agent_not_ready`. `pane.sh` returns BLOCKED and keeps the pane so the
  prompt can be answered; the brief was never sent, so close the pane and
  rerun the launch.
- After `--wait`, the question just answered can read as `blocked` for a
  moment, so a block in the first seconds of a resumed wait is not reported.
- A worker's report path does not exist until the worker writes it; take it
  from the first line `pane.sh` prints, never from a directory listing.
- Herdr agent names match `^[a-z][a-z0-9_-]{0,31}$`; anything else fails with
  `invalid_agent_name` and leaves an empty pane. `pane.sh` names each pane
  `<role>-<model>-<task>`, refuses one that would not fit, and finds the
  delegate column by the role prefix.
- Herdr's `done` can mean the turn ended while the TUI is still up; it is
  treated like `idle`.
- Headless `codex exec` waits for stdin forever unless given `< /dev/null` (or
  the prompt on stdin), so wrap it in a timeout.
- Codex ignores `plugins."<id>".enabled` for a remote plugin, in
  `config.toml` and through `-c` alike, and `codex exec` loads no remote
  plugins at all, so only a real pane shows what a worker sees.
- A Codex worker in a linked worktree asks approval for every `git add` and
  `git commit` (the metadata lives in the main repository's `.git`). Inspect
  the diff before approving.
- Herdr keeps no worker history (`herdr agent read --source scrollback` is
  empty); a Codex worker's commands and token totals are in its session log
  under `~/.codex/sessions/<date>/`.
