#!/usr/bin/env bash
# PreToolUse hook on Bash. `git add|checkout|commit|reset|restore -p` and
# `git stash -p` ask hunk by hunk, and nobody can answer here: the command
# waits on the prompt, or reads an empty stdin and does nothing. This refuses
# them.
#
# A textual guard, not a shell parser, built like pkill-guard.sh: heredoc
# bodies are dropped (command-text.sh), quoted strings replaced by Q, comments
# cut off, the rest cut into simple commands, and redirections and everything
# after ` -- ` dropped. `git` must be the command word (after assignments,
# `sudo`, `env` and the like, or a shell keyword), and only its global options
# may stand before the subcommand, so `git log -p`, `git stash show -p` and
# `echo git add -p` pass. Known limits, all on the side of letting a command
# through: a patch flag inside quotes or after a redirection, a global option
# with a separate operand other than -C and -c, and `xargs git add -p`. An
# unquoted option operand that reads `-p` (`git commit -m -p`) is refused.
set -euo pipefail

# shellcheck source=claude/hooks/command-text.sh
. "$(dirname "${BASH_SOURCE[0]}")/command-text.sh"

quoted="('[^']*'|\"[^\"]*\")"
while [[ $text =~ $quoted ]]; do text=${text/"${BASH_REMATCH[1]}"/ Q }; done
text=${text//$'\t'/ }

# A comment ends its line, separators and all.
comment='(^|[[:space:]])#'
lines=''
while IFS= read -r line; do
  [[ $line =~ $comment ]] && line=${line%%"${BASH_REMATCH[0]}"*}
  lines+="$line"$'\n'
done <<< "$text"

before='^[[:space:]]*(([[:alpha:]_][[:alnum:]_]*=[^[:space:]]*|Q|sudo|env|command|exec|time|nohup|if|then|else|elif|do|while|until|!|\{)[[:space:]]+)*'
git="$before"'([^[:space:]]*/)?git[[:space:]]+((-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*)(add|checkout|commit|reset|restore|stash)([[:space:]].*)?$'
patch='[[:space:]](-[[:alpha:]]*p[[:alpha:]]*|--patch)[[:space:]]'
reads='^[[:space:]]+(show|list)[[:space:]]'
sub=''
while IFS= read -r segment; do
  segment=${segment%%[<>]*}
  [[ $segment =~ $git ]] || continue
  name=${BASH_REMATCH[6]} rest="${BASH_REMATCH[7]} "
  rest="${rest%% -- *} "
  [ "$name" = stash ] && [[ $rest =~ $reads ]] && continue
  [[ $rest =~ $patch ]] || continue
  sub=$name
  break
done <<< "${lines//[;|&()\`]/$'\n'}"
[ -n "$sub" ] || exit 0

jq -n --arg reason "git $sub -p asks hunk by hunk and nobody can answer it here: it waits on the prompt, or reads an empty stdin and does nothing. To undo one change, restore the file from a copy made before the change (cp file backup; cp backup file) or edit it; to stage part of a file, use git apply --cached with a patch file." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
