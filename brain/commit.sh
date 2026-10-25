#!/usr/bin/env bash
# Commit a scanned memory tree without changing the shared index, then push.
set -euo pipefail
export LC_ALL=C

log() { printf 'brain: %s\n' "$*" >&2; }
refuse() { log "$*"; exit 1; }
if [ "$#" -ne 1 ]; then refuse 'usage: commit.sh <projects-dir>'; fi
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[ -d "$1" ] || exit 0
projects=$(cd -- "$1" && pwd)
cd -- "$projects"
# Do not discover a parent repository when the projects directory has no repo.
[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" = "$projects" ] || exit 0
[ "$(git config --bool brain.enabled 2>/dev/null || true)" = true ] || exit 0
[ "$(git symbolic-ref -q HEAD || true)" = refs/heads/main ] || refuse 'expected branch main'
old=$(git rev-parse -q --verify HEAD || true)

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export GIT_INDEX_FILE
GIT_INDEX_FILE=$(mktemp "$tmp/index.XXXXXX")
if [ -n "$old" ]; then git read-tree "$old"; else git read-tree --empty; fi
# Inspect HEAD's entries, not unrelated staging in the shared index.
git ls-files -ci --exclude-standard -z > "$tmp/ignored"
if [ -s "$tmp/ignored" ]; then
  while IFS= read -r -d '' file; do
    printf 'brain: refusing tracked ignored file %q\n' "$file" >&2
  done < "$tmp/ignored"
  exit 1
fi
git add -A -- .

secret=false
while IFS=$'\t' read -r name re; do
  if git grep --cached -l -z -E -e "$re" -- . > "$tmp/matches"; then
    while IFS= read -r -d '' file; do
      printf 'brain: refusing %q: secret (%s)\n' "$file" "$name" >&2
    done < "$tmp/matches"
    secret=true
  else
    result=$?
    [ "$result" -eq 1 ] || refuse 'secret scan failed'
  fi
done < "$here/patterns"
if "$secret"; then exit 1; fi

tree=$(git write-tree)
old_tree=$(git rev-parse -q --verify 'HEAD^{tree}' || true)
if [ "$tree" != "$old_tree" ]; then
  # No HEAD argument: --cached also works when the branch is unborn.
  git diff --cached --name-only -z > "$tmp/changed"
  keys=$(jq -rRs 'split("\u0000") | map(select(length > 0) | split("/")[0]) | unique | join(" ")' < "$tmp/changed")
  export GIT_AUTHOR_NAME=brain GIT_AUTHOR_EMAIL=brain@localhost
  export GIT_COMMITTER_NAME=brain GIT_COMMITTER_EMAIL=brain@localhost
  parents=()
  if [ -n "$old" ]; then parents=(-p "$old"); fi
  new=$(git -c commit.gpgsign=false commit-tree "$tree" ${parents[@]+"${parents[@]}"} -m "memory: $keys")
  if ! git update-ref refs/heads/main "$new" "$old" 2>/dev/null; then
    log 'branch moved during run; next run will retry'
    exit 0
  fi
  "$here/audit.sh" "$projects" > "$tmp/audit" 2>&1 || true
  while IFS= read -r line || [ -n "$line" ]; do log "$line"; done < "$tmp/audit"
fi

expected=$(git config --get brain.remote || true)
# --all also refuses an extra pushurl: git push would contact every one.
actual=$(git remote get-url --push --all origin 2>/dev/null || true)
[ -n "$expected" ] && [ "$actual" = "$expected" ] || refuse 'push URL differs from brain.remote'
if git rev-parse -q --verify '@{u}' > /dev/null 2>&1; then
  [ "$(git rev-list --count '@{u}..HEAD')" -gt 0 ] || exit 0
fi
if ssh-add -l > /dev/null 2>&1; then
  :
else
  result=$?
  case "$result" in
    1|2) log 'push deferred: no SSH key available'; exit 0 ;;
    *) refuse 'could not inspect SSH agent' ;;
  esac
fi
export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes'
if ! timeout 60 git push -u origin HEAD:main > "$tmp/push" 2>&1; then
  refuse 'push failed; next run will retry'
fi
