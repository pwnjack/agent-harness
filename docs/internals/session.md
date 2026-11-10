# The loop, session end and handover

## Design

- **One loop, eight skills.** `design` (brainstorm, `grill`, spec),
  `write-plan`, `build`, `review`, `wrap-up` (`handover`, `learn`). The
  global instructions name the loop; each skill ends by naming the next, and
  `test-skills.sh` checks both. Every skill runs for the user (`/name`) and
  for the agent alike. `delegate` is the manual for handing work to a pane.
- **One file per piece of work.** `design` writes the spec to
  `docs/specs/<slug>.md`, `write-plan` appends the plan to it, and `review`
  hands that one path to the reviewer.
- **One review per change.** `build` checks each task itself and commits it;
  `review` runs once on the whole branch, and earlier only on a task the plan
  marks risky.
- **Wrap-up is cleanup, not a report.** It verifies the final state,
  inventories what the session created (panes, briefs and reports, scratchpad
  and mockup files, servers and stacks, worktrees, branches), removes only
  that after looking at each item, confirms with command output, then runs
  `handover` and `learn`. Unmerged or unpushed work, other sessions' panes and
  stashes the session did not create are never touched.
- **Handover is one rolling note.** `handoff.md` in the project's memory has
  five parts in a fixed order: state, decisions, next, leftovers, pending from
  the user. It is rewritten in place; the brain keeps the earlier versions.
  `MEMORY.md` keeps one "Start here" pointer at it.
- **Size limits** follow the brain audit: the note stays under 8192 bytes and
  the index under 4096 bytes.
- **Only the orchestrator in the main checkout** runs `wrap-up`, `handover`
  or `learn`; a leaf worker or a worktree session reports instead.
