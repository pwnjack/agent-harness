# Delegation, models and advisor

## Design

- **Cross-family review.** Claude's work is reviewed by Codex and Codex's by
  Claude. With no usable Codex, a different Claude tier in a fresh context
  reviews, reported as same-family.
- **Blind review.** The reviewer never sees the implementer's report.
- **One review mandate.** Only `CLAUDE.global.md` requires a review.
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
  the prompt, for Claude and Codex alike, and asks for the list keys as arrays
  of strings; the check accepts any array. A malformed report is `NOREPORT`
  and is moved aside for a fresh one.
- **Model names.** Skills name aliases (`sonnet`) and Codex codenames (`sol`),
  never pinned IDs; `test-skills.sh` enforces this. `codex-model.sh` resolves
  a codename to the newest listed model of that name at launch and clamps the
  effort to what the model lists.
- **Model, then effort.** The skill's table picks the model per family by
  the hardest part of the work. Effort is chosen per task for every role,
  from starting points the skill lists; no level is fixed to a role. Past a
  model's reach, move up a model rather than raise effort.
- **Same choice in every runner.** The Agent-tool fallback outside Herdr
  gets the same model, effort and brief as a pane.
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

`claude/apply-settings.sh` deletes `advisorModel` on every merge, and
`claude/hooks/advisor-reset.sh` (`SessionStart`, matcher `startup`) clears it
whenever a non-worker Claude session starts, including a scripted
`claude -p`. Enable `/advisor fable` only in the one session doing the work.
The orchestrator proposes it with a reason; the user decides.

Claude workers launched by `pane.sh` get `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`
and `HARNESS_LEAF=1` through the `--settings` `env` object, which also turns
Superpowers off. The first disables their advisor tool; the second makes the
reset hook leave the user's choice alone.

## pane.sh behaviour

- On a Codex "hooks need review" screen, `pane.sh` sends Escape and resends
  the prompt once. Never answer that screen with
  "trust all"; that is the user's call.
- Quota is judged only when the worker is idle, against Codex's own error
  wording at the bottom of the screen.
- `--wait` and `--resume` keep the pane on REPORT; `DELEGATE_KEEP=0` makes
  `--wait` close it. QUOTA always closes it.
- A start that fails on a first-run folder-trust prompt is BLOCKED with the
  pane kept: answer the prompt there, then close the pane and rerun the
  launch, because the brief was never sent.
- A block in the first seconds of a resumed `--wait` is not reported.
- Herdr's `done` is treated like `idle`.
- The report path exists only once the worker writes it; take it from the
  first line `pane.sh` prints.
- Pane names follow `<role>-<model>-<task>` and must match
  `^[a-z][a-z0-9_-]{0,31}$`; `pane.sh` refuses any other name and finds the
  delegate column by the role prefix.
