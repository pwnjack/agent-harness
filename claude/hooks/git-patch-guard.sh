#!/usr/bin/env bash
# PreToolUse hook on Bash. `git add|checkout|commit|reset|restore -p` and
# `git stash -p` ask hunk by hunk, and nobody can answer here: the command
# waits on the prompt, or reads an empty stdin and does nothing. This refuses
# them.
#
# A textual guard, not a shell parser, built like pkill-guard.sh: heredoc
# bodies are dropped (command-text.sh), quoted strings replaced by Q, the rest
# cut into simple commands, comments, redirections and everything after ` -- `
# cut off. Only options and their values may stand between `git` and the
# subcommand, so `git log -p` and `git stash show -p` pass. `echo git add -p`
# unquoted is a known false refusal.
set -euo pipefail

# shellcheck source=claude/hooks/command-text.sh
. "$(dirname "${BASH_SOURCE[0]}")/command-text.sh"

quoted="('[^']*'|\"[^\"]*\")"
while [[ $text =~ $quoted ]]; do text=${text/"${BASH_REMATCH[1]}"/ Q }; done

git='(^|[[:space:]])([^[:space:]]*/)?git[[:space:]]+((-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*)(add|checkout|commit|reset|restore|stash)([[:space:]].*)?$'
patch='[[:space:]](-[[:alpha:]]*p[[:alpha:]]*|--patch)[[:space:]]'
reads='^[[:space:]]+(show|list)[[:space:]]'
comment='(^|[[:space:]])#'
sub=''
while IFS= read -r segment; do
  segment=${segment%%[<>]*}
  [[ $segment =~ $comment ]] && segment=${segment%%"${BASH_REMATCH[0]}"*}
  [[ $segment =~ $git ]] || continue
  name=${BASH_REMATCH[6]} rest="${BASH_REMATCH[7]} "
  rest="${rest%% -- *} "
  [ "$name" = stash ] && [[ $rest =~ $reads ]] && continue
  [[ $rest =~ $patch ]] || continue
  sub=$name
  break
done <<< "${text//[;|&()\`]/$'\n'}"
[ -n "$sub" ] || exit 0

jq -n --arg reason "git $sub -p asks hunk by hunk and nobody can answer it here: it waits on the prompt, or reads an empty stdin and does nothing. To undo one change, restore the file from a copy made before the change (cp file backup; cp backup file) or edit it; to stage part of a file, use git apply --cached with a patch file." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
