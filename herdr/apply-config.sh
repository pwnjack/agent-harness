#!/usr/bin/env bash
# Merge the tracked Herdr Card layout into Herdr's config, check it, and roll
# back if Herdr rejects the result. Usage: apply-config.sh (no arguments).
# Target: $HERDR_CONFIG_PATH, else $XDG_CONFIG_HOME/herdr/config.toml.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=${here%/*}

if ! command -v herdr >/dev/null 2>&1; then
  echo 'herdr: not installed, skipping'
  exit 0
fi

target=${HERDR_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}
export HERDR_CONFIG_PATH=$target
mkdir -p -- "$(dirname -- "$target")"
[ -f "$target" ] || : > "$target"
backup=$(mktemp "$target.XXXXXX")
keep=
trap '[ -n "$keep" ] || rm -f -- "$backup"' EXIT
cp -- "$target" "$backup"

# restore <why>: put the backup back; if that fails, keep it and say where it is.
restore() {
  if cp -- "$backup" "$target"; then
    echo "herdr: $1; restored $target"
  else
    keep=1
    echo "herdr: $1; could not restore $target, original kept at $backup" >&2
  fi
}

if ! bash "$repo/lib/toml-merge.sh" herdr "$target" "$here/sidebar.toml"; then
  restore 'merge failed'
  exit 1
fi

if ! check=$(herdr config check 2>&1); then
  restore 'config check failed'
  printf '%s\n' "$check"
  exit 1
fi

# A per-agent row set replaces the Card layout for that agent. Headers and
# keys are read as dotted paths of bare or wholly quoted segments; anything
# else is unreadable and matches nothing, and every header resets the scope,
# so only ui.sidebar.agents.rows_by_agent.<agent> warns.
for agent in claude codex; do
  if awk -v want="ui.sidebar.agents.rows_by_agent.$agent" '
    # path(s): dotted path of simple segments, quotes dropped; "!" if unreadable
    function path(s,   out, seg) {
      out = ""
      while (1) {
        sub(/^[ \t]+/, "", s)
        if (match(s, /^[A-Za-z0-9_-]+/)) seg = substr(s, 1, RLENGTH)
        else if (match(s, /^"[A-Za-z0-9_-]+"/) || match(s, /^\047[A-Za-z0-9_-]+\047/)) seg = substr(s, 2, RLENGTH - 2)
        else return "!"
        out = (out == "" ? seg : out "." seg)
        s = substr(s, RLENGTH + 1)
        sub(/^[ \t]+/, "", s)
        if (s == "") return out
        if (substr(s, 1, 1) != ".") return "!"
        s = substr(s, 2)
      }
    }
    { l = $0; sub(/^[ \t]+/, "", l) }
    l ~ /^\[/ && l ~ /\][ \t]*(#.*)?$/ {
      h = l; sub(/\]+[ \t]*(#.*)?$/, "", h); sub(/^\[+/, "", h)
      table = path(h)
      next
    }
    index(l, "=") {
      k = path(substr(l, 1, index(l, "=") - 1))
      if (k == "!" || table == "!") next
      if ((table == "" ? k : table "." k) == want) found = 1
    }
    END { exit !found }
  ' "$target"; then
    echo "herdr: warning: rows_by_agent.$agent in $target replaces the Card layout for $agent"
  fi
done

if herdr status server >/dev/null 2>&1; then
  herdr server reload-config >/dev/null
  echo 'herdr: reloaded config'
fi
