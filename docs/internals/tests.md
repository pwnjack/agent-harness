# Tests

`./test.sh` runs every tracked `test-*.sh`; `./test.sh --list` lists them. The
pre-commit gate runs them against a private export of the staged tree. Tests
use a temporary HOME, config and state directories and stub machine commands,
including Herdr, so they never install hooks or units on the host.

- `test-setup.sh`: upgrades and fresh installs, the fixed harness link with
  custom config paths, settings preservation, dry runs, the Herdr layout and
  Codex hooks wiring, the private Linux-only
  brain setup, refusal of foreign repositories, rendered units, repeat runs,
  and the removal block in `docs/internals/setup.md` run verbatim.
- `test-budgets.sh`: byte budgets for the global instructions, no dated
  history in tracked Markdown, and portable flags outside the exemption list.
- `brain/test-audit.sh`: memory index links, ordering, secret diagnostics,
  nested paths, excluded files and the 4096-byte warning.
- `brain/test-commit.sh`: whitelist, path and secret refusals, shared-index
  synchronisation, stale locks and concurrent updates, symlinked project
  paths, commit identity, push URL checks, SSH deferral, push diagnostics and
  retries.
- `claude/skills/test-skills.sh`: frontmatter, referenced files, no pinned
  IDs, plugin marketplaces.
- `claude/skills/delegate/test-delegate.sh`: model resolution, the opt-in
  gate, and every `pane.sh` verdict against a stub Herdr, including hook-review
  recovery, limit text that is not a quota hit, malformed reports, `--wait`
  and `--resume` keeping the pane, the trust-prompt BLOCKED, the worker
  settings that disable Superpowers and the advisor, and the pane placement
  (column of two, `crew` tabs of four, other workspaces ignored, fallback when
  `tab list` fails, role on every split and tab).
- `claude/skills/delegate/test-sdd-brief.sh`: every brief kind is filled and
  blind, bad ranges and changed templates are refused, hostile titles and
  file names stay literal; against stand-in templates. Under `./test.sh` the
  check against the installed plugin's own templates is skipped, because HOME
  is sandboxed; run the suite directly to include it.
- `claude/hooks/test-agent-guard.sh`: the guard denies inside Herdr, is silent
  outside it, and is registered once after two settings merges.
- `claude/hooks/test-pkill-guard.sh`: the guard denies `pkill -f` and `pgrep -f`
  without a bracketed pattern, lets other commands and malformed input through
  silently, and is registered once after two settings merges.
- `claude/hooks/test-advisor-reset.sh`: startup registration, removal of
  `advisorModel`, worker bypass, settings mode and malformed settings.
- `codex/test-codex-config.sh`: `memories = false`, preservation of unrelated
  settings and repeat merges.
- `herdr/test-sidebar-report.sh`: the reporter's complete token patch, role
  mapping, repository naming, deduplication, silence outside Herdr and the
  watchdog on a hung call.
- `test-driver.sh`: `test.sh` clears inherited Herdr environment variables
  before running the suites.
- `herdr/test-apply-config.sh`: the harness layout merge, rollback on a failed
  merge or config check, the backup kept when rollback fails, the `rows_by_agent` warning, reload and skipping without Herdr.
- `claude/test-statusline.sh`: the status line reports to the sidebar without
  changing what it prints.
- `codex/test-codex-hooks.sh`: the Codex sidebar hook (model slug, effort from
  the transcript, silence) and the `hooks.json` merge beside Herdr's entry.
- `lib/test-toml-merge.sh`: multi-line fragment values replacing one-line and
  multi-line target values, appended tables, inline tables kept verbatim,
  repeat merges, in-place rewrites and write errors.
