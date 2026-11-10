#!/usr/bin/env bash
# Driver and pre-commit failures must never silently skip checks.
set -uo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }

# The driver itself must also be isolated when this suite runs directly.
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"

mkdir -p -- "$tmp/clone"
cp -- "$repo/test.sh" "$tmp/clone/test.sh"
cat > "$tmp/clone/test-env.sh" <<'SH'
#!/usr/bin/env bash
env | grep -E '^(HERDR_CONFIG_PATH|HERDR_PANE_ID|HERDR_SOCKET_PATH|HARNESS_ROLE|HARNESS_SIDEBAR_SYNC)=' > "$TEST_DRIVER_ENV"
exit 0
SH
git -C "$tmp/clone" init -q && git -C "$tmp/clone" add test.sh test-env.sh || exit 1

TEST_DRIVER_ENV="$tmp/seen" HERDR_CONFIG_PATH="$tmp/sentinel.toml" HERDR_PANE_ID=w1:p1 \
  HERDR_SOCKET_PATH="$tmp/herdr.sock" HARNESS_ROLE=worker HARNESS_SIDEBAR_SYNC=1 \
  bash "$tmp/clone/test.sh" > "$tmp/output" 2>&1
if [ -f "$tmp/seen" ] && [ ! -s "$tmp/seen" ]; then ok 'suites see no inherited Herdr variables'
else no 'suites see no inherited Herdr variables'; cat -- "$tmp/seen" "$tmp/output" 2>/dev/null; fi

# A git stub gives the driver a successful, empty tracked-file listing.
mkdir -p -- "$tmp/bin"
real_git=$(command -v git)
cat > "$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
case "$*" in
  ls-files*) exit 0 ;;
  'rev-parse --show-toplevel') printf '%s\n' "$TEST_DRIVER_REPO" ;;
  'rev-parse --local-env-vars') printf 'GIT_DIR\n'; exit 1 ;;
  *) exec "$TEST_DRIVER_GIT" "$@" ;;
esac
SH
chmod +x -- "$tmp/bin/git"
for arg in '' --list; do
  if PATH="$tmp/bin:$PATH" bash "$tmp/clone/test.sh" ${arg:+"$arg"} > "$tmp/output" 2>&1; then
    no "empty suite list ($arg): driver must fail"
  elif grep -qF 'no test suites found' "$tmp/output"; then
    ok "empty suite list ($arg): driver fails with a diagnostic"
  else no "empty suite list ($arg): missing diagnostic"; fi
  cat -- "$tmp/output"
done

# The real exporter copies staged blobs, not the worktree, and leaves the
# source repository's index and worktree alone.
mkdir -p -- "$tmp/staged"
git -C "$tmp/staged" init -q -b main || exit 1
printf 'staged\n' > "$tmp/staged/f"
git -C "$tmp/staged" add f || exit 1
printf 'unstaged\n' > "$tmp/staged/f"
cp -- "$tmp/staged/.git/index" "$tmp/index-before"
if bash -- "$repo/githooks/snapshot.sh" "$tmp/staged" "$tmp/export" > "$tmp/output" 2>&1 \
   && [ "$(cat -- "$tmp/export/worktree/f")" = staged ] \
   && [ "$(git -C "$tmp/export/worktree" ls-files)" = f ] \
   && [ "$(git -C "$tmp/export/worktree" show :f)" = staged ] \
   && [ "$(cat -- "$tmp/staged/f")" = unstaged ] \
   && cmp -s -- "$tmp/index-before" "$tmp/staged/.git/index"; then
  ok 'snapshot exports staged content, lists it as tracked, leaves the source alone'
else no 'snapshot exports staged content, lists it as tracked, leaves the source alone'; cat -- "$tmp/output"; fi

# Exercise the real hook, with a tiny snapshot stand-in and a failing git read.
mkdir -p -- "$tmp/clone/githooks"
cp -- "$repo/githooks/pre-commit" "$tmp/clone/githooks/pre-commit"
cat > "$tmp/clone/githooks/snapshot.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p -- "$2/worktree"
printf 'touch -- "$TEST_DRIVER_RAN"\n' > "$2/worktree/test.sh"
SH
if TEST_DRIVER_REPO="$tmp/clone" TEST_DRIVER_GIT="$real_git" TEST_DRIVER_RAN="$tmp/ran" \
   PATH="$tmp/bin:$PATH" bash "$tmp/clone/githooks/pre-commit" > "$tmp/output" 2>&1; then
  no 'pre-commit refuses a failed local-env-vars read'
elif [ ! -e "$tmp/ran" ] && grep -qF 'could not read local Git environment' "$tmp/output"; then
  ok 'pre-commit refuses a failed local-env-vars read before running tests'
else no 'pre-commit failed local-env-vars read: tests ran or diagnostic missing'; fi
exit "$fail"
