# Review rubric

A reviewer reads this from its brief. Report findings only; edit no file.

## Scope

- Review what the brief names: a diff, a commit, a branch, or, for a lean
  review, whole files or folders.
- When the brief names a spec or plan, read it first. Something it requires
  that the change does not do, or does differently, is a `must`; something
  it rules out that the change adds is a `should`.
- Read the code the change touches, not only the diff: callers of every
  changed function, what it calls, its tests and docs. When a signature,
  output or behaviour changes, grep every caller; untouched code can break.
- Judge load against what the repository expects, from one person running a
  script to many processes at once, and say which load you assumed.

## Look for, most important first

1. **Bug:** a wrong result, a crash, a missed edge (empty, zero, the last
   item, whitespace, a path starting with `-`), a caller the change breaks,
   a fix in one caller while the shared code stays wrong.
2. **Risk:** security (injection, unquoted expansion, secrets, unchecked
   input), data loss (swallowed errors, writes in the wrong order, an
   overwrite with no backup).
3. **Load:** races between processes, state that only grows, work repeated
   per item, quadratic loops on large input.
4. **Missing test:** risky new logic (a branch, a parser, security, a data
   write, a bug fix) with no test that fails when it breaks. One good test,
   not coverage.
5. **Speed:** a real slowdown is a finding; a small win is nice to have.
6. **Lean:** code that should not exist or could be smaller.
   - delete: dead code, unused options or flags, speculative features
   - reuse: the repository already has it (name the path)
   - stdlib: the language, the shell or a standard tool already does it; a
     dependency for a few lines
   - yagni: an abstraction with one user, config nobody sets, a wrapper that
     only forwards
   - merge: near-copies that must change together
   - split: one function doing unrelated jobs; split by job, never by length
   - say once: comments or docs that repeat the code or each other

A lean finding keeps the behaviour: say how the simpler form handles what the
old one did (errors, edge input, the portability the repository requires), or
name what it drops.

## Before reporting

- Every finding needs a concrete case: this input or situation gives this
  wrong result, or these lines can go and nothing changes. No case, no
  finding.
- Re-read the lines: the caller exists, the value can be empty, the code is
  unused.
- Propose the smallest fix that works, preferring one that deletes code.
  Never add a layer, option or dependency the problem does not need.
- No style taste, no "consider", no vague worries. A documented, deliberate
  limit is a decision, not a finding, unless the expected load crosses it.

## Report

Number findings across all groups, so the user can pick ("fix 2 and 5").
Each is one string, in `concerns` when the report is JSON:

`<n>. <must|should|nice> <file>:<line>: <what the code does>. Problem: <the case>. Fix: <the smallest fix>. If skipped: <what happens>.`

- must: a bug, security, data loss, or a break at the expected load.
- should: risky code without a test, real slowness, duplication, mixed jobs,
  code that should not exist.
- nice: a small speed-up, a shorter form.

End the summary with `Verdict: ship.` or `Verdict: fix <numbers> first.`,
then `Lean: -<N> lines possible.` when there are lean findings, and
`Not checked: <what>` when something that mattered could not be checked.

## Lean review

When the brief asks for a lean review, look for group 6 only, on the files it
names, read whole. A bug found on the way is still reported, as must.
