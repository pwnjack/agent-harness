---
name: handover
description: Use when work passes to a later session, another agent or a person (session end, context running low, switching machines, "write a handover" or "handoff") and when the wrap-up skill reaches its record step.
---

# Handover

A handover is one note from which the next session, agent or person starts
without re-deriving anything. It is written to the project's memory
directory, the one named in the session's memory instructions, from the main
checkout. When the user names a reader or a place, the same note also goes
there.

## The note

One memory file `handoff-YYYY-MM-DD.md` with `type: project` and these six
parts, in this order. A part with nothing in it says "none" rather than
disappearing. When today's file already exists, read it first and update it
in place: keep every decision and pending item that still holds, replace
what changed, and move what no longer belongs to the history memory. It is
never overwritten unread.

1. **State.** Branch and commit of each line that matters: local, origin and
   wherever it is deployed. Open pull requests and issues. Worktrees, panes,
   servers or stacks still running, and why each one is still there.
2. **Shipped this session.** Each change with its pull request or commit.
3. **Decisions.** What the user decided, in their words where the wording
   matters, and what they declined, so it is not proposed again.
4. **Next.** What comes next in the user's order. The first item is ready to
   start: which skill opens it, which files or memories to read first.
5. **Leftovers.** Known defects, deferred items and untested paths.
6. **Pending from the user.** Checks only they can do, approvals, open
   questions.

Rules for the note:

- Dates are absolute (`YYYY-MM-DD`), never "today" or "yesterday".
- A fact the next session can verify names the command or identifier that
  verifies it (`git log -1`, a deployment id, a migration name).
- Nothing the repository already records: no git history, no file layout,
  no `CLAUDE.md` content. Link related memories with `[[name]]`.
- Under 8192 bytes, and so is every memory this skill writes, the history
  memory included. When the note would grow past that, the older material
  moves into the project's dated history memory; when the history memory
  would grow past that, it continues in a new file linked from the old one
  and from the index.

## The index

`MEMORY.md` has one **Start here** line pointing at the newest handover.
Replace the previous pointer; the previous handover stays listed under the
project's memories or its content is folded into the dated history memory.
The index stays under 4096 bytes: one line per memory, never memory content.

When the brain git directory exists under
`${XDG_STATE_HOME:-$HOME/.local/state}`, run the memory audit as the
`compound-learning` skill shows and fix what it reports.

## For a named reader or place

Write the same six parts there (a file in the repository, a pull request
body, a message) without personal details, host names or secrets. The memory
copy is still written.

## Red flags

| Thought | Reality |
|---|---|
| "The progress history already has it" | The history is a log; the handover is the one note to start from. Both are written. |
| "I'll summarise instead of listing commits" | A commit, a pull request number or a deployment id is what the next session verifies. |
| "The decision is obvious from the code" | The code shows what was built, not what the user declined. Write the declined options too. |
| "I'll append to the old handover" | A previous day's note is linked or folded into history; today's note is read and updated in place. |
