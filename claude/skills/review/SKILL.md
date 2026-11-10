---
name: review
description: One blind review of a change by the other model family against its spec or plan, then fix what holds. Use for "review this", "review the branch", "get codex to review", "lean review", /review, as the last step of the build skill, and before reporting any non-trivial change done.
---

# Review

One review per change, by a model that did not write it and has not seen
what the writer said about it. A change you would have made directly (a line,
a rename, a config tweak) needs none.

## What

The whole change, once, when it is complete:

- a branch: `git diff <main>...<branch>`, with its spec or plan file
- uncommitted work: `git diff HEAD`, plus `git status --short` for new files
- a commit: `git show <sha>`

Review a single task before the rest only when the plan marks it risky (a
data migration, auth or access rules, money, deleting user data).

## Who

The other family, model and effort from the `delegate` skill's table for
this diff: Claude's work (yours included) goes to Codex, Codex's to Claude.
With no usable Codex, a different Claude model reviews (`opus` for Sonnet's
work, `sonnet` for yours or Opus's); say the review was same-family.

## The brief

The goal, the acceptance criteria (the spec or plan path), what to review as
above, and this line. Never the implementer's report or test claims.

> Read `~/.claude/harness/claude/skills/review/rubric.md` and follow it.
> Report findings only; do not edit any file.

Run it as role `review` through the `delegate` skill.

## Then

1. Check every finding against the code yourself and drop what does not hold.
2. Fix every `must` that holds, and every gap against the spec or plan. A fix
   follows the lazy rules: root cause, smallest change, its test.
3. Re-run the verification commands. A fix that changed the design goes back
   to the same reviewer once; anything smaller does not.
4. Tell the user once: what was found, what held, what you fixed, and the
   remaining `should` and `nice` findings with the rubric's numbers, so they
   can pick ("fix 2 and 5").
5. Log the yield, one line:

   ```bash
   state=${XDG_STATE_HOME:-$HOME/.local/state}; mkdir -p "$state"
   printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$(basename "$PWD")" <model>-<effort> <found> <held> <fixed> \
     >> "$state/harness-reviews.tsv"
   ```

## Lean review

When the user asks for a lean or simplify review of existing code, send the
same rubric as task `lean` or `lean-<area>`, name the files or folders and
"lean review" in the brief, and fix nothing until the user picks.

Next, inside the loop: the `wrap-up` skill, or back to `build` for what the
user picked.
