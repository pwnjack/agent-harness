# Delegation, models and advisor

## Design

The rules an orchestrator follows are in the skills (`delegate`, `review`,
`build`); this file holds what the scripts do and why.

- **Review is cross-family and blind.** The reviewer reads
  `claude/skills/review/rubric.md` from its brief, so the rubric costs context
  only in the reviewer's pane, and never sees the implementer's report.
- **Every worker runs in a Herdr pane**, Claude and Codex alike, so the user
  can watch it. `pane.sh` spawns, prompts and waits in one background call,
  and ends with a `next:` line that tells the orchestrator what to do with the
  verdict, so that handling is not restated in the skill.
  The first worker splits the orchestrator's pane to the right and the second
  splits that worker, a column of two. Further workers go to `crew`, `crew-2`,
  `crew-3`… tabs of four (2×2) in the same workspace. A new worker splits the
  largest pane, along its longer side, so every pane is a half or a quarter;
  Herdr gives a closed worker's space to its sibling and closes a tab when its
  last pane closes. Each worker opens in the caller's directory, so a worktree
  is the worker's project root and sandbox. The Herdr-only
  `claude/hooks/agent-guard.sh` refuses the Agent tool; outside Herdr it is
  silent and the Agent tool is the Claude fallback, with the same model,
  effort and brief.
- **Recursion guards.** A Claude pane gets a leaf directive through
  `--append-system-prompt`; the brief's `[LEAF WORKER — DO NOT DELEGATE]` line
  and the leaf section of the global instructions back it up for both
  families and are the only guard on the Agent-tool fallback. A leaf never
  starts agents, so live checks that need a Claude or Codex session belong to
  the orchestrator.
- **Report contract.** `pane.sh` names the report path and its JSON keys in
  the prompt, for Claude and Codex alike, and asks for the list keys as arrays
  of strings; the check accepts any array. A malformed report is `NOREPORT`
  and is moved aside for a fresh one.
- **Model names.** Skills name aliases (`sonnet`) and Codex codenames (`sol`),
  never pinned IDs; `test-skills.sh` enforces this. `codex-model.sh` resolves
  a codename to the newest listed model of that name at launch and clamps the
  effort to what the model lists.
- **Opt-in models are an allow-list.** Only Claude `haiku`, `sonnet`, `opus`
  (`CLAUDE_STANDARD` in `pane.sh`) and Codex `luna`, `terra`, `sol`
  (`STANDARD` in `codex-model.sh`) run freely. Every other name, `fable`,
  `astra` and anything new, needs `DELEGATE_EXPENSIVE=1`, set only when the
  user asked. That covers a model Codex `inherit` or the degrade path would
  launch through `config.toml` (pinned with `-m` so the checked model runs)
  and a launch whose model cannot be determined.
- **Effort** is `low`, `medium`, `high` or `xhigh` for both families. Never
  `max`; never Codex `ultra`, which turns on its own delegation.
- **Review yield.** The `review` skill appends one line per review (date,
  repository, reviewer, findings, held, fixed) to `harness-reviews.tsv` under
  `XDG_STATE_HOME`.

## Advisor

`claude/apply-settings.sh` deletes `advisorModel` on every merge, and
`claude/hooks/advisor-reset.sh` (`SessionStart`, matcher `startup`) clears it
whenever a non-worker Claude session starts, including a scripted
`claude -p`. The hook writes a temporary file beside the settings and renames
it after filtering, preserving the file mode. Failed copies, filters or
renames leave the settings untouched and do not block startup.
`/advisor fable`, when the user asks for it, is enabled only in the one
session doing the work.

Claude workers launched by `pane.sh` get `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`
and `HARNESS_LEAF=1` through the `--settings` `env` object. The first disables
their advisor tool; the second makes the reset hook leave the user's choice
alone.

## pane.sh behaviour

- `pane.sh` sets `HARNESS_ROLE=<role>` on each worker pane, so the Herdr
  sidebar shows the worker's role.
- On a Codex "hooks need review" screen, `pane.sh` sends Escape and resends
  the prompt once. Never answer that screen with
  "trust all"; that is the user's call.
- Quota is judged only when the worker is idle, against Codex's own error
  wording in the last lines of text on the screen (blank lines do not count).
- `--wait` and `--resume` keep the pane on REPORT; `DELEGATE_KEEP=0` makes
  `--wait` close it. QUOTA always closes it. Whenever a pane is left open, the
  verdict line ends in ` kept`.
- A start that fails on a first-run folder-trust prompt is BLOCKED with the
  pane kept and its own `next:` line: the brief was never sent, so the launch
  is rerun after the prompt is answered.
- A block in the first seconds of a resumed `--wait` is not reported.
- A Claude worker idle while its own background work runs is not finished:
  while the last four lines of text show Claude Code's footer count
  (`· 1 shell, 1 monitor`, or a count opening the line, followed by `,`, `·`
  or the line end), the quiet window neither starts nor expires; a usage
  limit still ends it as QUOTA, and otherwise only TIMEOUT does. Once the
  count leaves the footer the full quiet window applies. Codex launches skip
  the check; `--wait` and `--resume` cannot tell the kind, so they apply it.
- Herdr's `done` is treated like `idle`. A turn can run between two polls,
  so a prompt has landed once Herdr's `completion_seq` (finished turns,
  whatever the focus; absent before the first) is higher than just before the
  prompt was sent, at launch or `--resume`, in any status; no report is then
  NOREPORT, not NOSTART. A Herdr without the field falls back to a `done` the
  pane was not already in before the prompt.
- The report path exists only once the worker writes it; take it from the
  first line `pane.sh` prints.
- Pane names follow `<role>-<model>-<task>` and must match
  `^[a-z][a-z0-9_-]{0,31}$`; `pane.sh` refuses any other name and finds the
  delegate column by the role prefix.
- Placement: no column worker splits the orchestrator right; fewer than two
  splits the largest column pane; a full column fills the first tab, in tab
  order, labelled `crew` or `crew-N` with fewer than four panes (tabs sharing
  a label included), else creates the first unused label (`crew`, `crew-2`…)
  with `herdr tab create --workspace` and starts the worker in its root pane.
  The workspace is `HERDR_WORKSPACE_ID`, or else the prefix of `HERDR_TAB_ID`
  (`<workspace>:<tab>`); with neither, the column stacks. A failing Herdr
  read falls back to splitting the last column pane down; a failed split or
  tab create is NOSTART.
- Launches started together are placed one at a time: `pane.sh` takes
  `flock` on `.place.lock` in the handoff dir (fd 9) from just before it
  counts the column until `herdr agent start` returns, and nothing placement
  starts (its subshell, `jq`, `herdr`) inherits the fd, so killing the launch
  frees the lock at once. After
  `DELEGATE_LOCK_WAIT` seconds (default 90) the launch goes ahead without it
  and prints a note; with no `flock` on PATH it goes ahead silently.
  `--wait` and `--resume` never lock. `flock` is util-linux, so this is
  Linux only, like the rest of `pane.sh`.
