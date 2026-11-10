# Tests

`./test.sh` runs every tracked `test-*.sh`; `./test.sh --list` lists them.
Both fail if no suites are found. The pre-commit gate runs them against a
private export of the staged tree and refuses a failed Git environment read.
Tests use a temporary HOME, config and state directories and stub machine
commands, including Herdr, so they never install hooks or units on the host.

- `test-setup.sh`: upgrades and fresh installs, the fixed harness link with
  custom config paths, settings preservation, dry runs, the Herdr layout and
  Codex hooks wiring, the private Linux-only
  brain setup, recovery of interrupted initialisation, refusal of foreign and
  symlinked repositories and orphaned git directories, rendered units (including
  a clone path with spaces), permission unions, Codex-only installs, absent tools
  and source archives, dry-run previews inside an unrelated parent repository,
  repeat runs, a symlinked whitelist refused on a repeat `--brain` run, and
  the removal block in `docs/internals/setup.md` run verbatim twice, including
  Codex-only installs, removal of empty hooks and permissions, removal of the
  Codex sidebar hooks with a malformed `hooks.json` left alone, and
  preservation of user rules and hooks.
- `test-budgets.sh`: byte budgets for the global instructions, no dated
  history in tracked Markdown, and portable flags outside the exemption list,
  with fixtures for combined sed flags, backticks and shell comments.
  The textual scanner does not parse heredoc bodies: prose quotes can affect
  later shell quote state. Scripts with such heredocs belong in `EXEMPT`.
- `brain/test-audit.sh`: relative and duplicate memory index links, ordering
  with older jq and newline-containing paths, secret diagnostics, symlinked
  files, unknown keys, unreadable files, patterns without a final newline,
  nested paths, nested `MEMORY.md` files, excluded files and the 4096-byte
  warning.
- `brain/test-commit.sh`: whitelist refresh (missing, altered, loosened and
  upstream-changed copies), refused refreshes (read-only directory, failed
  copy, symlinked or directory `.gitignore`), path and secret refusals,
  shared-index synchronisation, stale locks and concurrent updates, symlinked
  project paths, commit identity, push URL checks, SSH deferral, push
  diagnostics and retries, branch and parent-repository guards, hidden
  projects and patterns without a final newline.
- `claude/skills/test-skills.sh`: frontmatter, referenced files, no pinned
  IDs, plugin marketplaces, and the review rubric named in the delegate skill
  and kept report-only; the global instructions name all four skills; the
  three memory-writing skills carry the orchestrator-only gate; wrap-up names
  handover and the learning skill, and handover names its six parts; the learning skill and its audit path exist, its example honours
  the brain-present gate and config paths, derives the key
  from the repository root in subdirectories, and propagates audit failures.
- `claude/skills/delegate/test-delegate.sh`: model resolution (the catalogue
  under `CODEX_HOME` included), the opt-in gate, and every `pane.sh` verdict against a stub Herdr (a case over
  `CASE_BUDGET` seconds, default 5, fails), including hook-review
  recovery, limit text that is not a quota hit, malformed reports, a worker
  that finishes between polls (by `completion_seq`, focused or resumed, and by
  `done` without it), a late start and a trailing report inside the landing
  and quiet windows, a Claude worker idle on its own shell and monitor (held
  until the report, on `--wait` too, released when the footer count goes,
  ended by a usage limit, not held by its prose, a turn line or for Codex),
  `--wait` and `--resume` keeping the pane, the
  trust-prompt BLOCKED, the worker settings that disable Superpowers and the
  advisor, and the pane placement
  (column of two, `crew` tabs of four, duplicate `crew` labels, tabs created
  in the caller's workspace, the lowest free tab label, other
  workspaces ignored, the workspace taken from the tab id, fallback when
  `tab list` fails, role on every split and tab), and the placement lock
  (simultaneous launches stack in order, a killed holder frees it at once, a
  stuck lock times out with a note, no `flock` on PATH, release on every path
  a long-lived child of `agent start` does not keep it, and a launch killed
  during a blocked placement read leaves nothing holding it).
- `claude/skills/delegate/test-sdd-brief.sh`: every brief kind is filled and
  blind, bad ranges and changed templates are refused, hostile titles and
  file names stay literal, and the default template search follows
  `CLAUDE_CONFIG_DIR`; against stand-in templates and the installed plugin's
  templates when present. The suite isolates HOME, the config and state
  directories and Git configuration itself; `./test.sh` resolves the installed
  skills directory before sandboxing, passing it as `SDD_TEST_SKILLS`.
  That directory is only read; generated briefs stay in the temporary repo.
  Set `SDD_TEST_SKILLS` to select a directory explicitly; an absent plugin
  skips only the installed-template check.
- `claude/hooks/test-agent-guard.sh`: the guard denies inside Herdr, is silent
  outside it, and is registered once after two settings merges.
- `claude/hooks/test-pkill-guard.sh`: the guard denies `pkill -f` and `pgrep -f`
  without a bracketed pattern, lets other commands and malformed input through
  silently, sees past a here-string and a heredoc with a hyphenated
  delimiter, ends a heredoc body only at its exact terminator (leading tabs
  for `<<-`), and is registered once after two settings merges.
- `claude/hooks/test-commit-pipe-guard.sh`: the guard denies a `git commit`
  chained with `&&` or `||` after a pipeline, allows it under
  `set -o pipefail`, in a separate list or with the pipe after the commit,
  stays silent on other commands and malformed input, and is registered once
  after two settings merges with the `pkill -f` guard beside it.
- `claude/hooks/test-advisor-reset.sh`: startup registration, removal of
  `advisorModel`, worker bypass, atomic replacement with the settings mode
  preserved, failed copies and renames, symlinked settings left untouched,
  unset HOME and config, and malformed settings.
- `codex/test-codex-config.sh`: `memories = false`, preservation of unrelated
  settings and repeat merges.
- `herdr/test-sidebar-report.sh`: the reporter's complete token patch, role
  mapping, repository naming, deduplication, silence outside Herdr and the
  watchdog on a hung call.
- `test-driver.sh`: `test.sh` clears inherited Herdr environment variables,
  resolves the newest installed templates by version before sandboxing, and
  refuses an empty suite list; the staged-tree exporter copies staged content
  and leaves the source repository alone; pre-commit refuses a failed local
  Git environment read.
- `herdr/test-apply-config.sh`: the harness layout merge, rollback on a failed
  merge or config check, the backup kept when rollback fails, the
  `rows_by_agent` warning, reload and skipping without Herdr.
- `claude/test-statusline.sh`: the status line reports to the sidebar without
  changing what it prints.
- `codex/test-codex-hooks.sh`: the Codex sidebar hook (model slug, effort from
  the transcript, silence) and the `hooks.json` merge beside Herdr's entry.
- `lib/test-toml-merge.sh`: multi-line fragment values replacing one-line and
  multi-line target values, appended tables, inline tables kept verbatim,
  quoted keys and table names matched by their bare spelling, repeat merges,
  in-place rewrites and write errors.
