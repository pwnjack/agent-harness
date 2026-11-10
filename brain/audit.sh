#!/usr/bin/env bash
# Check memory index links, secret-shaped text, file sizes and cited home
# paths, read-only.
#   audit.sh <projects-dir> [project-key...]
#   audit.sh --here    this checkout's memory; silent without a brain or memory
set -euo pipefail
export LC_ALL=C

if [ "${1:-}" = --here ]; then
  [ -d "${XDG_STATE_HOME:-$HOME/.local/state}/agent-brain.git" ] || exit 0
  # Subdirectories and linked worktrees share the main checkout's memory.
  root=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p') || root=
  [ -n "$root" ] || root=$(pwd -P)
  set -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" "$(printf '%s' "$root" | tr -c '[:alnum:]' '-')"
  [ -d "$1/$2/memory" ] || exit 0
fi
if [ "$#" -lt 1 ]; then
  printf 'usage: audit.sh <projects-dir> [project-key...] | --here\n' >&2
  exit 2
fi
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
projects=$(cd -- "$1" && pwd)
shift
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
errors=0

error() {
  printf 'ERROR %s/memory/%s: %s\n' "$key" "$1" "$2"
  errors=1
}

# Older jq raw writers truncate embedded NULs; let printf emit separators.
sort_paths() {
  jq -cRs 'split("\u0000") | unique[] | select(length > 0)' |
    while IFS= read -r path; do
      printf '%s\n' "$path" | jq -jr '.'
      printf '\0'
    done
}

secrets() {
  local file=$1 path=$2 name re result
  if [ ! -r "$file" ]; then error "$path" 'cannot read file'; return 0; fi
  while IFS=$'\t' read -r name re || [ -n "$name" ]; do
    if grep -l -E -e "$re" -- "$file" > /dev/null 2>&1; then
      error "$path" "secret ($name)"
    else
      result=$?
      if [ "$result" -ne 1 ]; then
        error "$path" "secret scan failed ($name)"
        return 0
      fi
    fi
  done < "$here/patterns"
}

audit_project() {
  local key=$1 memory="$projects/$1/memory" index line target path file
  local link_re='\[[^]]*\]\(([^)]+\.md)\)' listed=() count=0 i found
  case "$key" in -tmp*) return ;; esac
  if [ ! -d "$memory" ]; then
    if "$explicit"; then error '' 'missing memory directory'; fi
    return 0
  fi
  index="$memory/MEMORY.md"
  if [ -L "$index" ] && [ ! -f "$index" ]; then
    error MEMORY.md 'symlink target is not a regular file'
  elif [ -f "$index" ] && [ ! -r "$index" ]; then
    error MEMORY.md 'cannot read file'
  elif [ -f "$index" ]; then
    # An index is prose, not frontmatter; collect every Markdown file link.
    while IFS= read -r line || [ -n "$line" ]; do
      while [[ $line =~ $link_re ]]; do
        target=${BASH_REMATCH[1]}
        line=${line#*"${BASH_REMATCH[0]}"}
        # Only relative file links refer to this memory directory.
        case "$target" in /*|\#*) continue ;; esac
        if [[ $target =~ ^[[:alpha:]][[:alnum:]+.-]*: ]]; then continue; fi
        target=${target#./}
        found=false
        for ((i=0; i<count; i++)); do
          if [ "${listed[$i]}" = "$target" ]; then found=true; break; fi
        done
        if "$found"; then continue; fi
        listed[$count]=$target
        count=$((count + 1))
      done
    done < "$index"
    for ((i=0; i<count; i++)); do
      target=${listed[$i]}
      if [ ! -f "$memory/$target" ]; then
        if [ -L "$memory/$target" ]; then error "$target" 'symlink target is not a regular file'
        else error "$target" 'missing file'; fi
      fi
    done
    if [ "$(wc -c < "$index")" -gt 4096 ]; then
      printf 'WARN %s/memory/MEMORY.md: over 4096 bytes\n' "$key"
    fi
    secrets "$index" MEMORY.md
  fi

  # Inspect symlinked files too, without descending into symlinked directories.
  find "$memory" -mindepth 1 -name '.*' -prune -o \
    \( -type f -o -type l \) -name '*.md' -print0 \
    | sort_paths > "$tmp/files"
  while IFS= read -r -d '' file; do
    path=${file#"$memory/"}
    # Only the root index was handled above; a nested MEMORY.md is a memory.
    [ "$path" != MEMORY.md ] || continue
    found=false
    for ((i=0; i<count; i++)); do
      if [ "${listed[$i]}" = "$path" ]; then found=true; break; fi
    done
    if [ -L "$file" ] && [ ! -f "$file" ]; then
      if ! "$found"; then error "$path" 'symlink target is not a regular file'; fi
      continue
    fi
    if ! "$found"; then error "$path" 'not in MEMORY.md'; fi
    secrets "$file" "$path"
    # One fact per file: a file this large has become a grab-bag to split.
    if [ -r "$file" ] && [ "$(wc -c < "$file")" -gt 8192 ]; then
      printf 'WARN %s/memory/%s: over 8192 bytes\n' "$key" "$path"
    fi
    # A memory citing a home path that is gone has outlived what it describes.
    # Only a whole backticked `~/path` counts: no spaces, placeholders or globs.
    if [ -r "$file" ]; then
      { grep -oE '`~/[^]`[:space:]<>*?[$]+`' -- "$file" 2>/dev/null || true; } | tr -d '`' | sort -u > "$tmp/cited"
      while IFS= read -r cited; do
        [ -e "$HOME/${cited#\~/}" ] || printf 'WARN %s/memory/%s: cites missing %s\n' "$key" "$path" "$cited"
      done < "$tmp/cited"
    fi
  done < "$tmp/files"
}

explicit=false
if [ "$#" -eq 0 ]; then
  for project in "$projects"/*; do
    [ -d "$project" ] || continue
    printf '%s\0' "${project##*/}"
  done > "$tmp/keys"
else
  explicit=true
  printf '%s\0' "$@" > "$tmp/keys"
fi
sort_paths < "$tmp/keys" > "$tmp/sorted-keys"
while IFS= read -r -d '' key; do
  audit_project "$key"
done < "$tmp/sorted-keys"
exit "$errors"
