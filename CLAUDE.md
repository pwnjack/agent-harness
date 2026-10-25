# Agent harness

This repository is a public manual for the agent: it describes what exists and
how to use it. Decisions, lessons, traps and history go to memory, never here. Before changing a part, read its file in
`docs/internals/`: `setup.md` (wiring, settings, plugins, removal), `brain.md`
(memory repository, learning skill), `delegation.md` (panes, models,
advisor), `tests.md` (suites).

This repository tracks only what was authored here: the `delegate` and
`compound-learning` skills, brain scripts, global instructions and curated
settings. Never track logins, memory, caches or tool-written configuration.
`./setup.sh` links and merges the harness into the installed tools;
`./setup.sh --dry-run` previews those changes.

- `claude/`: Claude Code global instructions, skills, hooks and settings.
- `codex/`: Codex global instructions and curated configuration.
- `brain/`: private memory audit, commit scripts and user timer templates.
- `githooks/`: staged-tree export and the pre-commit test gate.
- `docs/internals/`: one manual per part, read before changing it.

Run `./test.sh` before committing. It discovers every tracked `test-*.sh`,
prints one result per suite and shows the output of failing suites.
`./test.sh --list` lists suites without running them. The pre-commit hook
runs the same checks against a private export of the staged tree.

Scripts use `#!/usr/bin/env bash` and `set -euo pipefail`; tests use
`set -uo pipefail`. Target Bash 3.2 and jq. Avoid `mapfile`, associative arrays
(`declare -A`, `local -A`) and non-portable flags such as `sed -i`, `date -d`,
`stat -c`, `find -printf`, `chmod --reference` and `basename -a`.
Pass paths that may start with `-` after `--`. Iterate over tracked files
with `git ls-files -z` and `while IFS= read -r -d ''`.

Tests must never touch the real HOME, `~/.claude`, `~/.codex`, `~/.config`
or systemd. Set HOME, CLAUDE_CONFIG_DIR, CODEX_HOME, XDG_STATE_HOME and
XDG_CONFIG_HOME inside a temporary directory. Stub systemctl, uname, gh,
ssh-add and herdr on PATH; herdr prints `claude: current` and `codex: current`
and exits zero. Use `ok`/`no` helpers, `ok   <what>` / `FAIL <what>` output,
and `exit "$fail"`.

Use British prose and sentence-case headings in documentation. Keep commit
messages in `type(scope): lowercase summary` form; scopes are `harness`,
`brain`, `skills`, `delegate`, `setup` and `dotfiles`. No attribution trailers.
Never use `git stash` or force-push.
