#!/usr/bin/env bash
# The registered hook uses sh; enter Bash before enabling its shell options.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail

# A worker must leave the user's advisor choice alone. Interactive startup
# clears that choice for the new session, without blocking on broken settings.
(
  [ "${HARNESS_LEAF:-}" != 1 ] || exit 0
  target="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  [ -f "$target" ] || exit 0
  tmp=$(mktemp "$target.XXXXXX") || exit 0
  trap 'rm -f -- "$tmp"' EXIT
  if jq -e -s '
    if length == 1 and (.[0] | type == "object" and has("advisorModel"))
    then .[0] | del(.advisorModel)
    else empty end
  ' "$target" > "$tmp"; then
    cat -- "$tmp" > "$target" # Keep the settings file mode and inode.
  fi
) >/dev/null 2>&1 || :
exit 0
