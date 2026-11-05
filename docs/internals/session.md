# Session end and handover

## Design

- **Wrap-up is cleanup, not a report.** The `wrap-up` skill runs when the
  user ends a session in any words. It verifies the final state first, runs
  `compound-learning` for any unrecorded lesson, inventories what the session
  created (panes, briefs and reports, scratchpad and mockup files, servers
  and stacks, worktrees, branches), removes only that after looking at each
  item, confirms the tree is clean and synced with command output, records a
  handover, and reports in three parts: removed, kept and why, pending.
  Unmerged or unpushed work, other sessions' panes and stashes the session
  did not create are never touched.
- **Handover is one note.** The `handover` skill writes `handoff-<date>.md`
  into the project's memory with six parts in a fixed order: state, shipped,
  decisions, next, leftovers, pending from the user. `MEMORY.md` keeps one
  "Start here" pointer at the newest handover. It runs on its own when work
  passes on mid-session and as the record step of `wrap-up`. When the user
  names a reader or a place, the same note is also written there without
  personal details or secrets.
- **Size limits** follow the brain audit: a handover stays under 8192 bytes
  and the index under 4096 bytes; older material moves to the project's
  dated history memory.
- **Only the orchestrator in the main checkout** runs either skill; a leaf
  worker or a worktree session reports instead, as with `compound-learning`.
