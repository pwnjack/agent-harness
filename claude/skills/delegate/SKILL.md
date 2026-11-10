---
name: delegate
description: Hand implementation, review or exploration to another model (Claude or Codex) in a visible Herdr pane. Use for "have codex/sonnet do X", "send this to a worker", /delegate, and whenever the build or review skill hands work off.
---

# Delegate

Do trivial work, and ambiguous or architectural work, yourself. Hand off what
a brief can fully describe.

## Who

Pick the row by the hardest part of the task. The effort is where to start,
not a rule; a model or effort the user names wins.

| Work | Claude | Codex | Effort |
|---|---|---|---|
| Read-only: finding files, reading logs and test output, summarising | `haiku` | `luna` | `low` |
| Well-scoped code against a clear task; routine review | `sonnet` | `sol` | `medium` |
| Debugging, migrations, performance, security-bearing, cross-cutting, this harness, review of any of those, or unsure | `opus` | `sol` | `high` |

- Codex when the brief is self-contained; Claude when the work needs judgement
  about this repository's conventions.
- A worker that falls short: first make sure it can check its own work (a
  test, a build, a script). Then one step up: the next effort level, or from
  `high` the next model at `medium`. With no model above, `sol` goes to
  `xhigh` and Opus stops. If that falls short too, stop and tell the user.
- Only the names in the table run freely. Any other (`fable`, `astra`,
  anything new) runs only when the user asks for it by name, and `pane.sh`
  refuses it without `DELEGATE_EXPENSIVE=1`. Never effort `max` or `ultra`.

## The brief

Workers share none of this conversation. Write the brief to
`/tmp/delegate/<role>-<task>.brief.md`:

```
[LEAF WORKER — DO NOT DELEGATE]
## Goal          what must be true when done
## Context       repo path, the spec or plan file and the task number, relevant files, constraints
## Out of scope  what not to touch
## Acceptance criteria
## Verification  exact commands and expected output
```

A worker leaves its changes uncommitted; you commit after checking them.
Codex's sandbox blocks some sockets and the network: install dependencies and
fetch data first, name any check that cannot pass in the sandbox, and run
that check yourself afterwards.

## Running it

Inside Herdr (`HERDR_ENV=1`) every worker runs in a pane, never the Agent
tool. With `run_in_background: true`:

```bash
~/.claude/harness/claude/skills/delegate/pane.sh <claude|codex> <model> <effort> <role> <task> <brief>
```

Role is `impl`, `review`, `explore` or `fix`. Task is one or two `a-z0-9-`
words naming the work, the same for an implementer and its reviewer; the pane
is named `<role>-<model>-<task>`.

The script prints one verdict line, then the report or the worker's screen,
then a `next:` line. Do what `next:` says. Report the model and effort from
the verdict line.

For a fix round on the same worker, launch it with `DELEGATE_KEEP=1`, write
the findings to a file and run `pane.sh --resume <pane> <file>`. After two
rounds, start a fresh worker one step up.

## After any worker

Read the diff and re-run the verification commands yourself. A worker's
`tests_run` is a claim, not evidence, and so is any statement about existing
code ("the form already sends it"): check the ones the change depends on.
