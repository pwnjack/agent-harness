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
`*/memory/`, excluding hidden and `-tmp*` projects. The installed `.gitignore`
is kept byte-identical to `brain/gitignore` in the checkout the commit script
runs from: a missing or differing copy is replaced before anything is staged,
and the commit script refuses any tracked ignored file.

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

- ignores projects directories without their own enabled repository and
  refuses a HEAD outside `main`, including detached HEADs;
- refreshes a missing or differing `<projects>/.gitignore` from
  `brain/gitignore` (a temporary file in the same directory, then a rename),
  logs `brain: whitelist refreshed from the harness` and continues, so the
  commit records the new `.gitignore` through the usual validation and scan;
  a failed refresh, or a `.gitignore` that is a symlink, directory or other
  non-regular file, is refused untouched with
  `refusing missing or altered .gitignore whitelist`;
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
patterns by name, including symlinked Markdown files. Only relative file
links count as memory entries; repeated links are checked once. Symlinks to
regular files are scanned even outside memory: the audit checks what the
agent reads, while `commit.sh` stores only the link text. Dangling links and
links to non-regular targets get one diagnostic per path; symlinked directories
are never traversed. An explicit key without a memory directory is an error.
Unreadable files and scan errors are reported without stopping the remaining
audit. Patterns need no final newline. Findings exit 1; a clean audit exits 0.
It warns when a `MEMORY.md`
exceeds 4096 bytes (Claude loads only the start of the index), and when any
other memory file exceeds 8192 bytes (one fact per file; split it). The commit
script journals the audit after each commit; audit findings never undo a commit.

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
describes only what exists and how to use it; decisions, lessons, traps and
history go to memory.

When the brain git directory exists under `${XDG_STATE_HOME:-$HOME/.local/state}`,
the skill audits the main checkout's memory, if its directory exists, before
searching existing guidance. It derives the key from the first entry in
`git worktree list --porcelain`, so subdirectories and linked worktrees use
the main checkout's memory; outside Git it uses the physical project directory.
The projects directory honours `CLAUDE_CONFIG_DIR`, and each non-alphanumeric
path character becomes `-`.

Its injection guard covers the skill only: native memory capture and
auto-dream bypass it, and the audit does not establish provenance.
