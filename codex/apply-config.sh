#!/usr/bin/env bash
# Merge the tracked Codex settings fragments (codex/*.toml) into
# ~/.codex/config.toml, key by key, leaving everything else in that file alone.
#
# Codex rewrites config.toml itself (project trust, hook hashes, counters), so
# the file cannot be a tracked symlink without dirtying git on every session.
# Fragments hold single-line `key = value` entries under [table] headers; a key
# that exists in the target is replaced in place, a missing one is appended to
# its table, and a missing table is appended to the file. Idempotent, and a
# no-op when Codex is not installed.
set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${CODEX_HOME:-$HOME/.codex}/config.toml"

[ -d "$(dirname "$target")" ] || { echo "codex: not installed, skipping"; exit 0; }
[ -f "$target" ] || : > "$target"

shopt -s nullglob
fragments=("$src_dir"/*.toml)
[ "${#fragments[@]}" -gt 0 ] || exit 0

tmp="$(mktemp "$target.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk '
  function key(l) { sub(/^[ \t]+/, "", l); sub(/[ \t]*=.*/, "", l); return l }
  function flush(t,   i) {            # append fragment keys the table lacked
    for (i = 1; i <= n[t]; i++) if (!done[t, i]) { print line[t, i]; done[t, i] = 1 }
  }
  function blanks() { printf "%s", held; held = "" }
  # net [ minus ] outside strings and comments: >0 means a multi-line value opened
  function delta(s,   o) {
    gsub(/"([^"\\]|\\.)*"|\047[^\047]*\047/, "", s); sub(/#.*/, "", s)
    o = gsub(/\[/, "", s); return o - gsub(/\]/, "", s)
  }
  # a value with its trailing comment and all blanks removed, for comparison only
  function norm(s) { sub(/^[^=]*=/, "", s); sub(/[ \t]*#[^"\047]*$/, "", s); gsub(/[ \t]/, "", s); return s }
  FNR == 1 { file++; tab = "" }
  file <= nfrag {
    if ($0 ~ /^[ \t]*\[/) {
      tab = $0; sub(/^[ \t]*/, "", tab); sub(/[ \t]*(#.*)?$/, "", tab)
      if (!(tab in seen)) { seen[tab]; order[++ntab] = tab }
    } else if ($0 !~ /^[ \t]*(#|$)/ && tab != "") {
      i = ++n[tab]; line[tab, i] = $0; name[tab, i] = key($0)
    }
    next
  }
  { target = 1 }
  skip > 0  { skip += delta($0); next }                  # rest of a replaced multi-line value
  depth > 0 { blanks(); print; depth += delta($0); next } # inside a kept multi-line value
  /^[ \t]*$/ { held = held $0 "\n"; next }   # hold blank lines so appended keys sit above them
  /^[ \t]*\[/ {
    if (tab in n) flush(tab)
    blanks()
    tab = $0; sub(/^[ \t]*/, "", tab); sub(/[ \t]*(#.*)?$/, "", tab)
    present[tab]; print; next
  }
  /^[ \t]*[A-Za-z0-9_."-]+[ \t]*=/ && (tab in n) {
    blanks(); k = key($0)
    for (i = 1; i <= n[tab]; i++) if (name[tab, i] == k) {
      done[tab, i] = 1
      if (norm($0) == norm(line[tab, i])) { print; depth = delta($0) }   # same value: keep comments/spacing
      else { print line[tab, i]; skip = delta($0) }
      next
    }
  }
  { blanks(); print; depth += delta($0) }
  END {
    if (target && (tab in n)) flush(tab)
    blanks()
    for (j = 1; j <= ntab; j++) {
      t = order[j]; if (t in present) continue
      if (target) print ""
      print t; flush(t); target = 1
    }
  }
' nfrag="${#fragments[@]}" "${fragments[@]}" "$target" > "$tmp"

if cmp -s "$tmp" "$target"; then
  echo "codex: config.toml already up to date"
else
  cat "$tmp" > "$target"   # rewrite in place: keeps the file's mode and inode
  echo "codex: merged $(basename -a "${fragments[@]}" | paste -sd' ') into $target"
fi
