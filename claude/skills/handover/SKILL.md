---
name: handover
description: Write the one note the next session, agent or person starts from. Use when work passes on (session end, context running low, switching machines, "write a handover" or "handoff", /handover) and when the wrap-up skill reaches its record step.
---

# Handover

A handover is one note from which the next session starts without
re-deriving anything. It is the memory file `handoff.md` (`type: project`) in
the project's memory directory, the one named in the session's memory
instructions. Run it only as the orchestrator in the main checkout; a leaf
worker or a worktree session puts the same five parts in its report instead.

There is one note per project and it is rewritten, not appended to: read it
first, keep every decision and pending item that still holds, replace what
changed, delete what is done. The brain, where it is set up, keeps the old
versions.
Nothing to pass on (no open work, no decision, nothing pending) means no
handover: say so and stop.

## The note

Five parts, in this order. A part with nothing in it says "none".

1. **State.** Branch and commit of each line that matters: local, origin and
   wherever it is deployed. Open pull requests and issues. Worktrees, panes,
   servers or stacks still running, and why each one is still there.
2. **Decisions.** What the user decided, in their words where the wording
   matters, and what they declined, so it is not proposed again.
3. **Next.** What comes next in the user's order. The first item is ready to
   start: which skill opens it, which files or memories to read first.
4. **Leftovers.** Known defects, deferred items and untested paths, each
   with the file, function or screen it lives in.
5. **Pending from the user.** Checks only they can do, approvals, open
   questions.

Rules for the note:

- Dates are absolute (`YYYY-MM-DD`), never "today" or "yesterday".
- A fact the next session can verify names the command or identifier that
  verifies it (`git log -1`, a deployment id, a migration name).
- Nothing the repository already records: no list of what shipped, no git
  history, no file layout, no `CLAUDE.md` content. Link related memories with
  `[[name]]`.
- Under 8192 bytes. A decision that outlives the work it came from moves to
  its own memory; the rest is deleted when it stops being true.

## The index

`MEMORY.md` has one **Start here** line pointing at `handoff.md`, with the
date and a one-line hook. The index stays under 4096 bytes: one line per
memory, never memory content. Then run
`~/.claude/harness/brain/audit.sh --here` and fix what it reports.

## For a named reader or place

When the user names a reader or a place (a file in the repository, a pull
request body, a message), write the same five parts there too, without
personal details, host names or secrets.

Next, at session end: the `learn` skill.
