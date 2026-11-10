---
name: wrap-up
description: Use when the user ends a session in any words (finalize, wrap up, conclude, close the session, done for today, goodbye, clean everything up before we go).
---

# Wrap-up

A wrap-up is a cleanup task that ends in a report, not a status report that
ends in suggestions. When it finishes, everything this session created and
no longer needs is gone, the tree is clean and synced, and the next session
can start from memory alone. Run it only as the orchestrator in the main
checkout; a leaf worker or a worktree session reports what it would clean
instead. Nothing is pushed or merged that the user has not asked for.

## Steps, in order

1. **Verify the final state.** `git status --short` shows what is
   uncommitted; `git log --oneline @{upstream}..` shows what is unpushed.
   Re-run the project's checks only if the tree changed since they last
   passed in this session. Unmerged or unpushed work is never deleted: it
   goes under pending in the report.
2. **Inventory what this session created**, by category, and look at each
   item before deciding:

   | Category | How to look |
   |---|---|
   | Worker panes | `herdr pane list`; only panes this session started (the names from `pane.sh`) |
   | Briefs and reports | `ls /tmp/delegate`; only this session's files |
   | Scratchpad and mockup files | the session's scratchpad directory and any mockup directory it served |
   | Servers and local stacks | `ss -ltnp` for listeners; the launch output for PIDs |
   | Worktrees | `git worktree list` |
   | Branches | `git branch --merged <main>` locally; `git branch -r --merged <main>` on origin |

3. **Clean up**, only what this session made:
   - Panes: `herdr pane close <pane>` for finished worker panes. Another
     session's pane is never yours, whatever its state.
   - Processes: find the PID first, then `kill <pid>` in its own call. Stop a
     local stack with its own stop command. Never `pkill -f` a pattern: it
     matches the shell running it and the rest of the command never runs.
   - Files: remove this session's briefs, reports, scratchpad files and
     mockup directories.
   - Git, in this order: switch the main checkout to the main branch;
     inspect each worktree of this session with `git status --short
     --ignored` there (a copy of an environment file or any other file this
     session put there goes with the worktree; a unique uncommitted change
     stays, with the worktree, and is listed under pending); `git worktree
     remove` it; then `git branch -d` each merged branch, `git push origin
     --delete` its remote copy, and `git remote prune origin`. A branch
     still checked out in a worktree cannot be deleted, which is why the
     worktree goes first. Unmerged branches, other people's branches and
     stashes you did not create stay.
   - An item that stays gets a reason in the report: a gitignored mockup a
     spec refers to, a worktree the user asked to keep, a stack with data.
4. **Confirm.** The tree is clean, the current branch and the main branch
   match their origin copies, no worker pane or server of this session is
   left. Show the commands and their output; a claim without output is not
   confirmation.
5. **Record.** Run the `handover` skill; it writes nothing when nothing
   passes on.
6. **Learn.** Run the `learn` skill for every correction, defect or harness
   friction of this session that is not recorded yet. It is also where a
   harness improvement gets proposed.
7. **Report** in three parts: removed, kept and why, pending (for the user
   or the next session). Nothing in the pending part is a cleanup you could
   have done.

## Red flags

| Thought | Reality |
|---|---|
| "I'll report the state and suggest the deletions" | The user asked for a finished state. Suggesting hands the cleanup back; do it and report what went. |
| "The branch is merged, so the worktree can go unchecked" | Look first: a worktree can hold a unique uncommitted change, which stays, beside a copied environment file, which goes. |
| "`pkill -f` is quicker" | It kills its own shell. PID first, then `kill`. |
| "That pane looks finished, close it" | Only panes this session started. |
| "The handover can wait for next time" | Without it the next session re-derives everything. Write it now. |
| "Memory says finalized, no need to show output" | Confirmation is command output, not a sentence. |
