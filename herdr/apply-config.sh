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
trap 'rm -f -- "$backup"' EXIT
cp -- "$target" "$backup"

bash "$repo/lib/toml-merge.sh" herdr "$target" "$here/sidebar.toml"

if ! check=$(herdr config check 2>&1); then
  cp -- "$backup" "$target"
  echo "herdr: config check failed; restored $target"
  printf '%s\n' "$check"
  exit 1
fi

# A per-agent row set replaces the Card layout for that agent. Headers and
# keys are normalised (comments, spaces and quotes dropped) and joined, so
# only the full ui.sidebar.agents.rows_by_agent.<agent> namespace matches.
for agent in claude codex; do
  if awk -v want="ui.sidebar.agents.rows_by_agent.$agent" '
    function norm(s) { gsub(/[ \t"\047]/, "", s); return s }
    { l = $0; sub(/^[ \t]+/, "", l) }
    l ~ /^\[[^]]*\][ \t]*(#.*)?$/ {
      h = l; sub(/\][ \t]*(#.*)?$/, "", h); sub(/^\[+/, "", h)
      if (h ~ /^[A-Za-z0-9_. "\047-]+$/) table = norm(h)
      next
    }
    index(l, "=") {
      k = substr(l, 1, index(l, "=") - 1)
      if (k !~ /^[A-Za-z0-9_. "\047-]+$/) next
      k = norm(k)
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
