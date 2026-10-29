#!/usr/bin/env bash
# Usage: toml-merge.sh <label> <target> <fragment>...
# Merge tracked TOML fragments into <target> (created empty if missing), key by
# key, leaving everything else in that file alone.
#
# Fragments hold `key = value` entries under [table] headers; a key that exists
# in the target is replaced in place, a missing one is appended to its table,
# and a missing table is appended to the file. A fragment value may span lines
# when its key line opens an array with `[`; it ends where the brackets balance
# and replaces the whole target value. Comment lines inside a fragment value
# are not supported. Idempotent; the target is rewritten in place, so it keeps
# its mode and inode. Messages are prefixed with <label>.
set -euo pipefail

[ "$#" -ge 3 ] || { echo 'usage: toml-merge.sh <label> <target> <fragment>...' >&2; exit 2; }
label=$1 target=$2
shift 2
fragments=("$@")

[ -f "$target" ] || : > "$target" \
  || { echo "$label: cannot create $target" >&2; exit 1; }
tmp="$(mktemp "$target.XXXXXX")" \
  || { echo "$label: cannot write next to $target" >&2; exit 1; }
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
  FNR == 1 { file++; tab = ""; open = 0 }
  file <= nfrag {
    if (open > 0) {                    # continuation of a multi-line fragment value
      line[tab, i] = line[tab, i] "\n" $0; multi[tab, i] = 1; open += delta($0)
    } else if ($0 ~ /^[ \t]*\[/) {
      tab = $0; sub(/^[ \t]*/, "", tab); sub(/[ \t]*(#.*)?$/, "", tab)
      if (!(tab in seen)) { seen[tab]; order[++ntab] = tab }
    } else if ($0 !~ /^[ \t]*(#|$)/ && tab != "") {
      i = ++n[tab]; line[tab, i] = $0; name[tab, i] = key($0); open = delta($0)
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
      # same one-line value: keep comments/spacing; a multi-line fragment value always replaces
      if (!((tab, i) in multi) && norm($0) == norm(line[tab, i])) { print; depth = delta($0) }
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
  echo "$label: ${target##*/} already up to date"
else
  # rewrite in place: keeps the file's mode and inode
  cat "$tmp" > "$target" || { echo "$label: cannot write $target" >&2; exit 1; }
  names=
  for fragment in "${fragments[@]}"; do
    names="${names:+$names }${fragment##*/}"
  done
  echo "$label: merged $names into $target"
fi
