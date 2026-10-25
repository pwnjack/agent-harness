#!/usr/bin/env bash
# Check memory index links, secret-shaped text and the index size, read-only.
set -euo pipefail
export LC_ALL=C

if [ "$#" -lt 1 ]; then
  printf 'usage: audit.sh <projects-dir> [project-key...]\n' >&2
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

secrets() {
  local file=$1 path=$2 name re result
  while IFS=$'\t' read -r name re; do
    if grep -l -E -e "$re" -- "$file" > /dev/null; then
      error "$path" "secret ($name)"
    else
      result=$?
      if [ "$result" -ne 1 ]; then return "$result"; fi
    fi
  done < "$here/patterns"
}

audit_project() {
  local key=$1 memory="$projects/$1/memory" index line target path file
  local link_re='\[[^]]*\]\(([^)]+\.md)\)' listed=() count=0 i found
  case "$key" in -tmp*) return ;; esac
  [ -d "$memory" ] || return 0
  index="$memory/MEMORY.md"
  if [ -f "$index" ]; then
    # An index is prose, not frontmatter; collect every Markdown file link.
    while IFS= read -r line || [ -n "$line" ]; do
      while [[ $line =~ $link_re ]]; do
        target=${BASH_REMATCH[1]}
        line=${line#*"${BASH_REMATCH[0]}"}
        target=${target#./}
        listed[$count]=$target
        count=$((count + 1))
      done
    done < "$index"
    for ((i=0; i<count; i++)); do
      target=${listed[$i]}
      if [ ! -f "$memory/$target" ]; then error "$target" 'missing file'; fi
    done
    if [ "$(wc -c < "$index")" -gt 4096 ]; then
      printf 'WARN %s/memory/MEMORY.md: over 4096 bytes\n' "$key"
    fi
    secrets "$index" MEMORY.md
  fi

  # Sort NUL-delimited paths with jq: portable and safe for spaces/newlines.
  find "$memory" -mindepth 1 -name '.*' -prune -o \
    -type f -name '*.md' ! -name MEMORY.md -print0 \
    | jq -jRs 'split("\u0000") | sort[] | select(length > 0) | . + "\u0000"' > "$tmp/files"
  while IFS= read -r -d '' file; do
    path=${file#"$memory/"}
    found=false
    for ((i=0; i<count; i++)); do
      if [ "${listed[$i]}" = "$path" ]; then found=true; break; fi
    done
    if ! "$found"; then error "$path" 'not in MEMORY.md'; fi
    secrets "$file" "$path"
  done < "$tmp/files"
}

if [ "$#" -eq 0 ]; then
  for project in "$projects"/*; do
    [ -d "$project" ] || continue
    printf '%s\0' "${project##*/}"
  done > "$tmp/keys"
else
  printf '%s\0' "$@" > "$tmp/keys"
fi
jq -jRs 'split("\u0000") | unique[] | select(length > 0) | . + "\u0000"' \
  < "$tmp/keys" > "$tmp/sorted-keys"
while IFS= read -r -d '' key; do
  audit_project "$key"
done < "$tmp/sorted-keys"
exit "$errors"
