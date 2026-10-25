# Brain and learning

## Brain

The brain is the private `git@github.com:pwnjack/agent-brain.git` repository.
Its worktree is `<config>/projects`, where Claude already writes memory; its
git directory is `~/.local/state/agent-brain.git` (or under `XDG_STATE_HOME`).
This public repository holds only the scripts, patterns, whitelist and unit
templates. Memory, lessons and history never belong here.

`./setup.sh --brain` is opt-in and Linux-only. Before changing anything it
requires `gh repo view pwnjack/agent-brain --json visibility -q .visibility`
to report `PRIVATE`. It runs `git init -b main --separate-git-dir`, sets
`origin`, `brain.remote` and `brain.enabled=true`, and commits the exact
`brain/gitignore` as `brain: start`. It reuses its own gitfile, refuses any
other `.git`, and refreshes `<config>/projects/.gitignore` when the tracked
whitelist has changed. A re-run changes nothing else. Plain setup creates no
brain and never enables auto-dream (it does not disable an existing setting). Never run `--brain` on a work machine.

The whitelist admits only `.gitignore` and non-hidden Markdown beneath
`*/memory/`, excluding `-tmp*` projects. Keep the installed `.gitignore`
byte-identical to `brain/gitignore`: the commit script refuses a missing or
altered copy and any tracked ignored file.

The rendered service runs `brain/commit.sh <projects-dir>`. The timer fires
two minutes after login (`OnStartupSec=2min`) and every thirty minutes
(`OnUnitActiveSec=30min`); enabling it fires it at once. Units live in
`~/.config/systemd/user/`; they are generated machine files and must never be
tracked in the dotfiles. Inspect runs with:

```bash
systemctl --user status brain-commit.timer
journalctl --user -u brain-commit
```

`brain/commit.sh`:

- builds the candidate tree in a temporary index, ignoring unrelated staging;
- refuses any candidate path other than `.gitignore` or a non-hidden
  `<key>/memory/**/*.md` outside `-tmp*`, so a nested `.gitignore` cannot
  admit other files;
- scans the candidate tree with `git grep --cached` and the named patterns in
  `brain/patterns`; a match refuses the commit and logs the path and pattern
  name, never the value;
- commits as `brain <brain@localhost>`, naming the changed project keys, and
  moves `main` with `git update-ref <new> <old>`: a branch that moved during
  the run exits successfully and retries next time; any other update failure
  logs Git's error and exits unsuccessfully;
- then resets the shared index to the new tree: unrelated staging in the brain
  is discarded, worktree files are untouched, and a failed reset is logged
  without undoing the commit;
- pushes only when every push URL equals `brain.remote`, with a 60-second
  timeout, `GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND='ssh -o BatchMode=yes'`;
  `ssh-add -l` returning 1 or 2 defers the push, and a failed push logs the
  last ten lines of Git's output and retries next run.

`brain/audit.sh <projects-dir> [project-key...]` is read-only. It reports
memories absent from `MEMORY.md`, index links to missing files and secret
patterns by name, and warns when a `MEMORY.md` exceeds 4096 bytes (Claude
loads only the start of the index). The commit script journals the audit
after each commit; audit findings never undo a commit.

Off switches, independent and history-preserving:
`systemctl --user disable --now brain-commit.timer` stops automatic commits;
`git -C <config>/projects config brain.enabled false` makes the script a
no-op; deleting `autoDreamEnabled` from the live settings stops auto-dream.

## Learning

The `compound-learning` skill turns an evidenced correction into exactly one
lasting prevention, the first that applies of: a check, project
documentation, a skill, a global instruction, memory. It runs only in the
main checkout's orchestrator; workers and worktree sessions report lessons
instead. Harness changes are diff proposals that need the user's yes, then a
cross-family review in a worktree before merging. Any harness text it adds
states the rule and its reason only; a story worth keeping goes to memory.
Its injection guard covers the skill only: native memory capture and
auto-dream bypass it, and the audit does not establish provenance.

Not built; add one only when real recurrences call for it: a shared
`skills/` directory for both agents, lesson capture on the Codex side, review
of each auto-dream diff, a private cross-project lessons file imported by the
global `CLAUDE.md`, a report tool, and the macOS port of the exempt files.
