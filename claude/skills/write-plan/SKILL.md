---
name: write-plan
description: Turn an approved spec into an ordered list of small, checkable tasks. Use for "write the plan", "plan this", "break this down", /write-plan, and after the design skill's spec is approved.
---

# Write plan

From an approved spec to tasks someone with none of this conversation could
carry out. The plan is appended to the spec's file under `## Plan`, so the
reviewer reads one file. No spec and the change is small and clear: write the
plan alone, with a two-line goal on top.

## 1. Scope

Read the code the spec touches, then list every place the change must reach:
callers, tests, fixtures, config, exports, migrations, docs, copy. A place
missing here is a bug later. Anything the spec did not foresee goes back to
the user before the plan is written.

## 2. Tasks

The fewest tasks that cover the scope, in an order where the project's checks
pass after each one. Each task is one commit:

```
### <n>. <what is true when it is done>
Files:  <exact paths: create, change, delete>
Reuses: <the existing helper, component or pattern, with its path>
Check:  <the command to run and what it must show>
Risky:  <only for a data migration, auth or access rules, money, or deleting
        user data: what could go wrong>
```

- Name things exactly: paths, functions, tables, routes, the copy a screen
  shows.
- No code in the plan, except a signature or schema that two tasks share.
- A task that adds non-trivial logic names its test in Check.
- Say which tasks do not depend on each other; those may run in parallel.
- Deleting and reusing come before adding. A task with nothing to check is
  not a task: fold it into the one that needs it.

## 3. Check the plan against the spec

Every Acceptance line of the spec is covered by a task's Check, and no task
does something the spec's Out of scope names. Say which line each one covers.

## 4. Approval

The user approves the plan or changes it. Next: the `build` skill.
