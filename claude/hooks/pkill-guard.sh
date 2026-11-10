#!/usr/bin/env bash
# PreToolUse hook on Bash. `pkill -f` and `pgrep -f` match whole command
# lines, and the shell running the command carries the pattern in its own, so
# they find that shell: pkill kills it (exit 144) and nothing after it runs.
# This refuses them unless the pattern brackets a character ('[n]ext dev'),
# which no longer matches its own text.
#
# A textual guard, not a shell parser. In order: heredoc bodies are dropped
# and backslash-newlines joined (command-text.sh), quoted strings replaced by
# Q (or QB when they hold a bracketed character), the rest cut into simple
# commands at newlines, ; | & ( ) and backticks, comments and redirections cut
# off. A pkill or pgrep word (bare or after a path) with an f option and no
# bracketed pattern is refused. `echo pkill -f x` unquoted is a known false
# refusal.
set -euo pipefail

# shellcheck source=claude/hooks/command-text.sh
. "$(dirname "${BASH_SOURCE[0]}")/command-text.sh"

# Quoted strings become Q, or QB when they hold a bracketed character.
quoted="('[^']*'|\"[^\"]*\")"
bracketed='\[[^]]+\]'
while [[ $text =~ $quoted ]]; do
  match=${BASH_REMATCH[1]}
  token=Q
  [[ $match =~ $bracketed ]] && token=QB
  text=${text/"$match"/ $token }
done

tool='(^|[[:space:]])([^[:space:]]*/)?(pkill|pgrep)([[:space:]].*)?$'
full='[[:space:]](-[[:alpha:]]*f[[:alnum:]]*|--full)[[:space:]]'
comment='(^|[[:space:]])#'
placeholder='[[:space:]]QB[[:space:]]'
unsafe=0
while IFS= read -r segment; do
  segment=${segment%%[<>]*}
  [[ $segment =~ $comment ]] && segment=${segment%%"${BASH_REMATCH[0]}"*}
  [[ $segment =~ $tool ]] || continue
  rest="${BASH_REMATCH[4]} "
  [[ $rest =~ $full ]] || continue
  [[ $rest =~ $bracketed || $rest =~ $placeholder ]] && continue
  unsafe=1
  break
done <<< "${text//[;|&()\`]/$'\n'}"
[ "$unsafe" = 1 ] || exit 0

jq -n --arg reason "pkill -f / pgrep -f match the shell running this command, whose command line holds the pattern: pkill kills it (exit 144) and the rest never runs. Find the PID first (ss -ltnp, pgrep -x <name>) and kill it in its own call, or bracket a character: pkill -f '[n]ext dev'." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
