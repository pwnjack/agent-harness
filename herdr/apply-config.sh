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
mkdir -p -- "${target%/*}"
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

# A per-agent row set replaces the Card layout for that agent.
for agent in claude codex; do
  if awk -v agent="$agent" '
    /^[ \t]*\[/ { t = $0; gsub(/[ \t\[\]]/, "", t); next }
    { l = $0; sub(/^[ \t]+/, "", l) }
    t ~ /(^|\.)rows_by_agent$/ && index(l, agent) == 1 && l ~ "^" agent "[ \t]*=" { found = 1 }
    index(l, "rows_by_agent." agent) && l ~ "rows_by_agent\\." agent "[ \t]*=" { found = 1 }
    END { exit !found }
  ' "$target"; then
    echo "herdr: warning: rows_by_agent.$agent in $target replaces the Card layout for $agent"
  fi
done

if herdr status server >/dev/null 2>&1; then
  herdr server reload-config >/dev/null
  echo 'herdr: reloaded config'
fi
