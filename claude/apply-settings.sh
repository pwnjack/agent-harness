#!/usr/bin/env bash
# Merge the tracked Claude Code settings (claude/settings.json) into
# ~/.claude/settings.json, removing advisorModel and keeping other live keys.
#
# The tracked copy holds only the settings authored here.
# Objects merge key by key. Permission allow/ask/deny arrays are ordered unions
# (live entries first, then tracked entries, without duplicates). Other arrays
# use the tracked value, except hooks: each tracked hook group is appended after
# removing live hooks that run the same script (matched by file name). Other
# hooks sharing a group survive; empty groups are dropped. Re-running never
# duplicates a hook and replaces stale absolute-path copies. Live hooks running
# missing scripts under ~/.claude/hooks are dropped. Idempotent, and a no-op
# when neither Claude Code nor its config directory is present.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/settings.json"
target="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

command -v claude >/dev/null || [ -d "$(dirname "$target")" ] || { echo "claude: not installed, skipping"; exit 0; }
command -v jq >/dev/null || { echo "claude: jq is required to merge settings" >&2; exit 1; }
mkdir -p "$(dirname "$target")"
[ -s "$target" ] || echo '{}' > "$target"

tmp="$(mktemp "$target.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cp -p -- "$target" "$tmp"

# A fresh machine has no hooks directory yet: that is "no hooks", not an error.
dir="$(dirname "$target")/hooks"
present=$(for f in "$dir"/*.sh; do
  [ -e "$f" ] || [ -L "$f" ] || continue
  printf '%s\n' "${f##*/}"
done | jq -R . | jq -s .)

jq -s --argjson present "${present:-[]}" '
  def script: (.command // "") | (capture("(?<s>[^/\\s\"\\x{27}]+\\.sh)").s // .);
  .[0] as $live | .[1] as $mine
  | ($live * ($mine | del(.hooks))) | del(.advisorModel)
  | reduce ["allow", "ask", "deny"][] as $kind (.;
      if $live.permissions[$kind] != null or $mine.permissions[$kind] != null then
        .permissions[$kind] = (reduce (($live.permissions[$kind] // [])
          + ($mine.permissions[$kind] // []))[] as $rule ([];
            if index($rule) == null then . + [$rule] else . end))
      else . end)
  | .hooks = (($live.hooks // {}) as $lh
      | reduce (($mine.hooks // {}) | to_entries[]) as $e ($lh;
          ([$e.value[].hooks[]? | script]) as $ours
          | .[$e.key] = ([(.[$e.key] // [])[]
                          | .hooks |= map(select(script as $s | ($ours | index([$s])) == null))
                          | select((.hooks | length) > 0)]
                         + $e.value)))
  | .hooks |= (with_entries(.value |= [.[]
        | .hooks |= map(select(((.command // "") | capture("\\.claude/hooks/(?<n>[^/\\s\"\\x{27}]+\\.sh)").n // null) as $n
                               | $n == null or ($present | index([$n])) != null))
        | select((.hooks | length) > 0)])
      | with_entries(select(.value | length > 0)))
' "$target" "$src" > "$tmp"

if cmp -s "$tmp" "$target"; then
  echo "claude: settings already up to date"
else
  mv "$tmp" "$target"
  echo "claude: merged tracked settings into $target"
fi
