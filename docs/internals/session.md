# The loop, session end and handover

## Design

- **One loop, four steps.** `design` (brainstorm, `grill`, spec),
  `write-plan`, `build`, `review`. Work takes the lightest entry that
  fits: none when it is trivial, `build` when it is small, `write-plan` when
  it is decided but takes more than three lines of scope, and `design` for
  the rest, where more than one approach is sound and a wrong guess would
  cost real rework. The global instructions hold that rule, the three
  skills each repeat their side of it in their first paragraph, each skill
  ends by naming the next, and `test-skills.sh` checks all of it. Every skill
  runs for the user (`/name`) and for the agent alike. `delegate` is the
  manual for handing work to a pane.
- **Small work has no file.** `build` takes a change whose scope fits in
  three lines straight from the request. Those lines are its plan and its
  acceptance, and `review` writes them into the reviewer's brief. A bug's
  cause is found before they are written. An open detail is settled by the
  smallest reading, named in those lines; the user is asked first only when a
  wrong guess cannot be undone.
- **Session end is outside the loop.** `wrap-up` (`handover`, `learn`)
  closes a session, not a change, so `build` and `review` hand over to the
  user's merge decision or the next change.
- **One file per piece of planned work.** `design` writes the spec to
  `docs/specs/<slug>.md`, `write-plan` appends the plan to it, or writes the
  plan alone there for a decided change, and `review` hands that one path to
  the reviewer.
- **One review per change.** `build` checks each task itself and commits it;
  `review` runs once on the whole branch, and earlier only on a task the plan
  marks risky.
- **Wrap-up is cleanup, not a report.** It verifies the final state,
  inventories what the session created (panes, briefs and reports, scratchpad
  and mockup files, servers and stacks, worktrees, branches), removes only
  that after looking at each item, confirms with command output, then runs
  `handover` and `learn`. Unmerged or unpushed work, other sessions' panes and
  stashes the session did not create are never touched. A session that
  changed nothing and started nothing skips the inventory, the cleanup and
  the confirmation, unless it was resumed or compacted.
- **Handover is one rolling note.** `handoff.md` in the project's memory has
  five parts in a fixed order: state, decisions, next, leftovers, pending from
  the user. It is rewritten in place; the brain keeps the earlier versions.
  `MEMORY.md` keeps one "Start here" pointer at it.
- **Size limits** follow the brain audit: the note stays under 8192 bytes and
  the index under 4096 bytes.
- **Only the orchestrator in the main checkout** runs `wrap-up`, `handover`
  or `learn`; a leaf worker or a worktree session reports instead.
