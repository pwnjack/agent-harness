#!/usr/bin/env bash
# Codex hook: report model, effort and repo to the Herdr sidebar.
# Reads the hook JSON on stdin, prints nothing (UserPromptSubmit stdout is
# added to the prompt) and always exits 0.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat) || exit 0
field() { printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null || true; }
model=$(field model)
cwd=$(field cwd)
transcript=$(field transcript_path)
[ -n "$cwd" ] || exit 0

# gpt-6.1-sol becomes "Sol 6.1"; any other slug passes through.
if [[ $model =~ ^gpt-([0-9.]+)-([a-z]+)$ ]]; then
  codename=${BASH_REMATCH[2]}
  first=$(printf '%s' "${codename:0:1}" | tr '[:lower:]' '[:upper:]')
  model="$first${codename:1} ${BASH_REMATCH[1]}"
fi

# The last record may be half-written, so take the last of the final five
# turn_context lines that parses.
effort=''
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  lines=$(grep -F '"type":"turn_context"' -- "$transcript" 2>/dev/null | tail -n 5) || lines=''
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    value=$(printf '%s' "$line" | jq -r '.payload.effort // empty' 2>/dev/null) || continue
    effort=$value
  done <<EOF2
$lines
EOF2
fi

HARNESS_SIDEBAR_SYNC=1 bash "$(dirname "${BASH_SOURCE[0]}")/../../herdr/sidebar-report.sh" \
  "$cwd" "$model" "$effort" >/dev/null 2>&1 || true
exit 0
