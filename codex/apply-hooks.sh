#!/usr/bin/env bash
# Add the sidebar hook to ~/.codex/hooks.json for the events that change what
# the sidebar shows, keeping every other hook (Herdr's own included). Writes
# only when something changed. Usage: apply-hooks.sh (no arguments).
set -euo pipefail

target="${CODEX_HOME:-$HOME/.codex}/hooks.json"
cmd="bash '$HOME/.claude/harness/codex/hooks/sidebar.sh'"

[ -d "$(dirname "$target")" ] || { echo "codex: not installed, skipping"; exit 0; }

if [ -f "$target" ]; then
  jq -e 'type == "object"' "$target" >/dev/null 2>&1 \
    || { echo "codex: hooks.json is not valid JSON; left unchanged"; exit 1; }
  current=$(cat -- "$target")
else
  current='{"hooks":{}}'
fi

merged=$(printf '%s' "$current" | jq --arg cmd "$cmd" '
  .hooks = (.hooks // {})
  | reduce ("SessionStart", "UserPromptSubmit", "PostToolUse", "Stop") as $event (.;
      if any(.hooks[$event][]?.hooks[]?; .command == $cmd) then .
      else .hooks[$event] = ((.hooks[$event] // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
      end)')

if [ -f "$target" ] && [ "$(printf '%s' "$current" | jq -S .)" = "$(printf '%s' "$merged" | jq -S .)" ]; then
  echo "codex: hooks.json already up to date"
  exit 0
fi
printf '%s\n' "$merged" > "$target"
echo "codex: added sidebar hooks to $target"
