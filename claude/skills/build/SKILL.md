---
name: build
description: Implement an approved plan task by task, directly or through workers, then review the whole change and fix what the review finds. Use for "build it", "implement the plan", "go", /build, and after the write-plan skill's plan is approved.
---

# Build

From an approved plan to a reviewed branch. No plan and the change is small
and clear: the request is the plan; say its scope in three lines and start.
No plan and it is not small: the `write-plan` skill first.

## 1. Branch

Work on a branch off the project's integration branch, never on it. Use a
worktree only when another session shares the checkout or tasks run in
parallel. Running this skill is the user's yes to commit on that branch;
nothing is pushed or merged unasked.

## 2. Each task, in the plan's order

1. **Do it.** Yourself when it is small or needs this conversation;
   otherwise hand it to a worker with the `delegate` skill, the plan file and
   the task number in the brief. One task at a time; go parallel only when
   the user asks, each worker in its own worktree and branch, merged in the
   plan's order.
2. **Check it.** Run the task's Check yourself and read the diff: it does the
   task, all of it, and nothing else. Red or incomplete is fixed now, not
   after the next task.
3. **Commit it**, chained to the check: one commit per task, in the
   project's message style.
4. **Risky task** (the plan says so): run the `review` skill on that commit
   before building on it.

When the plan turns out wrong (a missing place, a task that cannot pass),
stop, fix the plan with the user, then go on. Never improvise past it.

## 3. The whole change

1. Run the project's full checks.
2. Walk the spec's Acceptance lines: each one is shown true by a command or
   by looking at the running thing, not by the diff.
3. Run the `review` skill on the branch against the spec and plan. It fixes
   what holds and reports the rest.

## 4. Report

What was built, per Acceptance line; what the review found and what was
fixed; what the user must still check by hand. Next: the `wrap-up` skill, or
the user's merge decision.
