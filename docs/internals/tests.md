# Tests

`./test.sh` runs every tracked `test-*.sh`; `./test.sh --list` lists them.
Both fail if no suites are found. The pre-commit gate runs them against a
private export of the staged tree and refuses a failed Git environment read.
Tests use a temporary HOME, config and state directories and stub machine
commands, including Herdr, so they never install hooks or units on the host.

- `test-setup.sh`: upgrades and fresh installs, the fixed harness link with
  custom config paths, settings preservation, dry runs, the Herdr layout and
  Codex hooks wiring, the private Linux-only
  brain setup, refusal of foreign repositories, rendered units, repeat runs,
  and the removal block in `docs/internals/setup.md` run verbatim.
- `test-budgets.sh`: byte budgets for the global instructions, no dated
  history in tracked Markdown, and portable flags outside the exemption list,
  with fixtures for combined sed flags, backticks and shell comments.
  The textual scanner does not parse heredoc bodies: prose quotes can affect
  later shell quote state. Scripts with such heredocs belong in `EXEMPT`.
- `brain/test-audit.sh`: memory index links, ordering, secret diagnostics,
  nested paths, excluded files and the 4096-byte warning.
- `brain/test-commit.sh`: whitelist, path and secret refusals, shared-index
  synchronisation, stale locks and concurrent updates, symlinked project
  paths, commit identity, push URL checks, SSH deferral, push diagnostics and
  retries.
- `claude/skills/test-skills.sh`: frontmatter, referenced files, no pinned
  IDs, plugin marketplaces, and the review rubric named in the delegate skill
  and kept report-only.
- `claude/skills/delegate/test-delegate.sh`: model resolution, the opt-in
  gate, and every `pane.sh` verdict against a stub Herdr, including hook-review
  recovery, limit text that is not a quota hit, malformed reports, `--wait`
  and `--resume` keeping the pane, the trust-prompt BLOCKED, the worker
  settings that disable Superpowers and the advisor, and the pane placement
  (column of two, `crew` tabs of four, other workspaces ignored, fallback when
  `tab list` fails, role on every split and tab), and the placement lock
  (simultaneous launches stack in order, a killed holder frees it at once, a
  stuck lock times out with a note, no `flock` on PATH, release on every path
  a long-lived child of `agent start` does not keep it, and a launch killed
  during a blocked placement read leaves nothing holding it).
- `claude/skills/delegate/test-sdd-brief.sh`: every brief kind is filled and
  blind, bad ranges and changed templates are refused, hostile titles and
  file names stay literal; against stand-in templates and the installed
  plugin's templates when present. `./test.sh` resolves the installed skills
  directory before sandboxing HOME and config, passing it as `SDD_TEST_SKILLS`.
  That directory is only read; generated briefs stay in the temporary repo.
  Set `SDD_TEST_SKILLS` to select a directory explicitly; an absent plugin
  skips only the installed-template check.
- `claude/hooks/test-agent-guard.sh`: the guard denies inside Herdr, is silent
  outside it, and is registered once after two settings merges.
- `claude/hooks/test-pkill-guard.sh`: the guard denies `pkill -f` and `pgrep -f`
  without a bracketed pattern, lets other commands and malformed input through
  silently, and is registered once after two settings merges.
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
  refuses an empty suite list; pre-commit refuses a failed local Git
  environment read.
- `herdr/test-apply-config.sh`: the harness layout merge, rollback on a failed
  merge or config check, the backup kept when rollback fails, the `rows_by_agent` warning, reload and skipping without Herdr.
- `claude/test-statusline.sh`: the status line reports to the sidebar without
  changing what it prints.
- `codex/test-codex-hooks.sh`: the Codex sidebar hook (model slug, effort from
  the transcript, silence) and the `hooks.json` merge beside Herdr's entry.
- `lib/test-toml-merge.sh`: multi-line fragment values replacing one-line and
  multi-line target values, appended tables, inline tables kept verbatim,
  repeat merges, in-place rewrites and write errors.
