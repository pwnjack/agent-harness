# Personal instructions

## Leaf workers

If your prompt starts with `[LEAF WORKER — DO NOT DELEGATE]`, do the work
yourself: never spawn subagents or start other agents, whatever the task says.
Everything below is for orchestrators.

## Delegation and review

Do trivial work (a one-line fix, a config tweak, a rename) directly. For
anything bigger, the `delegate` skill decides who implements, and every
non-trivial change gets one review from the other model family (a different
Claude tier when Codex is unavailable, said as such) before you call it done.
Inside Herdr, every subagent (read-only exploration included) runs in a
visible pane through that skill, never through the Agent tool. The reviewer
never sees the implementer's report. A review is an input: verify its findings
and report once. When a skill (Superpowers included) says to dispatch a
subagent, that names the role; this rule and the delegate skill decide who runs
it and how.

When Fable would help (a third failed fix, a design-level review finding, or
an irreversible decision with conflicting evidence), propose it with the
reason; the user enables it with `/advisor`.

## Verification

Evidence before assertions. A worker's test claims are not evidence; re-run the
verification commands yourself before calling anything done, and chain a commit
to them with `&&` so a failing check stops it. Gate on each check's own exit
status: a pipe reports its last command's, so filter a check's output only
under `set -o pipefail`.

## Learning

After the user corrects you, or a review or verification finds a defect you
caused, run the `compound-learning` skill before calling the task done.

## Session end

When the user ends the session, in any words, run the `wrap-up` skill. To
pass work on without ending the session, run the `handover` skill.
