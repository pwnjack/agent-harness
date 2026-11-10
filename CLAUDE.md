# Agent harness

This repository is a public manual for the agent: it describes what exists and
how to use it. Decisions, lessons, traps and history go to memory, never here.
Before changing a part, read its file in `docs/internals/`: `setup.md`
(wiring, settings, removal), `brain.md` (memory repository, learning skill),
`delegation.md` (panes, models, advisor), `session.md` (the loop, wrap-up and
handover). Each test suite says what it covers in its header.

This repository tracks only what was authored here: the skills, hooks, status
line, brain scripts, Herdr and Codex wiring, global instructions and curated
settings. Never track logins, memory, caches or tool-written configuration.
`./setup.sh` links and merges the harness into the installed tools;
`./setup.sh --dry-run` previews those changes.

- `claude/`: the global instructions both agents read, skills, hooks, status
  line and settings.
- `codex/`: Codex curated configuration and sidebar hook.
- `brain/`: private memory audit, commit scripts and user timer templates.
- `herdr/`: Herdr sidebar layout and reporter.
- `githooks/`: staged-tree export and the pre-commit test gate.
- `lib/`: shared scripts, such as the TOML merger.
- `docs/internals/`: one manual per part, read before changing it.

Run `./test.sh` before committing. It discovers every tracked `test-*.sh`,
prints one result per suite and shows the output of failing suites.
`./test.sh --list` lists suites without running them. A behaviour change
ships with a test that fails without it; prove that by reverting the change
in a scratch copy before asking for review. The pre-commit hook runs the same
checks against a private export of the staged tree.

Scripts use `#!/usr/bin/env bash` and `set -euo pipefail`; tests use
`set -uo pipefail`; the Agent-tool guard hook alone is POSIX `sh`. Target
Bash 3.2 and jq; `githooks/snapshot.sh` and the delegate scripts also need
`python3`. Avoid `mapfile`, associative arrays (`declare -A`, `local -A`),
non-portable flags such as `sed -i`, `date -d`, `stat -c`, `find -printf`,
`chmod --reference` and `basename -a`, and `\x` escapes in sed expressions
(BSD sed reads them literally; quote an ANSI-C `$'\e'` instead).
Pass paths that may start with `-` after `--`. Iterate over tracked files
with `git ls-files -z` and `while IFS= read -r -d ''`.

Tests must never touch the real HOME, `~/.claude`, `~/.codex`, `~/.config`
or systemd. Set HOME, CLAUDE_CONFIG_DIR, CODEX_HOME, XDG_STATE_HOME and
XDG_CONFIG_HOME inside a temporary directory. Stub systemctl, uname, gh,
ssh-add and herdr on PATH; herdr prints `claude: current` and `codex: current`
and exits zero. Use `ok`/`no` helpers, `ok   <what>` / `FAIL <what>` output,
and `exit "$fail"`.

Use British prose and sentence-case headings in documentation. Keep commit
messages in `type(scope): lowercase summary` form; the scope names the part
changed (`delegate`, `skills`, `brain`, `setup`, `statusline`, `herdr`,
`codex`, `budgets`, `docs`), or `harness` for a cross-cutting change. No
attribution trailers. Never use `git stash` or force-push.
