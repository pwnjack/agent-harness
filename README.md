# Agent harness

A personal setup for working with AI coding agents (Claude Code and Codex),
kept in one repository so a machine can be wired up, checked and unwired with
a script. It is shared as a reference: read it, borrow from it, adapt it. It
is not a framework and makes no promise of stability.

## What is in it

- **Global instructions** for both agents (`claude/CLAUDE.global.md`): write
  the least code that solves the whole problem, and the loop below.
- **Skills** (`claude/skills/`), each a command for the user and a step the
  agent takes on its own:
  - `design` brainstorms an idea, has `grill` challenge it, and writes a spec.
  - `write-plan` turns the spec into small, checkable tasks.
  - `build` implements them, directly or through workers (`delegate`, each in
    a visible pane).
  - `review` gets the change reviewed blind by the other model family and
    fixes what holds.
  - `wrap-up` cleans up at the end of a session, `handover` writes the note
    the next session starts from, and `learn` turns a correction into the
    narrowest lasting fix, in the harness itself when that is where it
    belongs.
- **Hooks** (`claude/hooks/`) that refuse a few commands known to go wrong:
  `pkill -f` matching its own shell, a `git commit` chained after a pipeline
  without `pipefail`, and the Agent tool where workers should run in panes.
- **A status line**, a sidebar layout and curated settings for Claude Code,
  Codex and Herdr.
- **Brain scripts** (`brain/`) that audit and commit a private memory
  repository. The memory itself is never tracked here.

Only what was written here is tracked. Logins, memory, caches and anything a
tool writes for itself stay out.

## Trying it

It needs Bash, Git and `jq`; Python 3 for the delegate scripts. Claude Code,
Codex and Herdr (the terminal workspace whose panes the workers run in) are
each optional: setup skips whatever is missing.

```sh
./setup.sh --dry-run   # show what would be linked and merged
./setup.sh             # do it
```

Setup links the skills and global instructions into the agents' config
directories and merges the tracked settings into the live ones. A file
already in the way is moved aside, never deleted. To undo it all, follow
"Removing the harness" in [`docs/internals/setup.md`](docs/internals/setup.md).

## Finding your way

- [`docs/internals/setup.md`](docs/internals/setup.md): wiring, settings,
  removal.
- [`docs/internals/delegation.md`](docs/internals/delegation.md): panes,
  models, reviews.
- [`docs/internals/session.md`](docs/internals/session.md): the loop,
  wrap-up and handover.
- [`docs/internals/brain.md`](docs/internals/brain.md): the memory repository
  and the learning skill.

`CLAUDE.md` and `AGENTS.md` at the root are the instructions agents read when
they work on this repository itself.

## Tests

```sh
./test.sh          # every suite, one line each
./test.sh --list   # list the suites
```

The suites run in a temporary home directory and never touch real
configuration. A pre-commit hook runs them against the staged tree.
