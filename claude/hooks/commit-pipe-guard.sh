#!/usr/bin/env bash
# PreToolUse hook on Bash. A pipeline reports only its last command's status,
# so `check | tail -5 && git commit` commits when the check fails. This refuses
# a command with a pipe anywhere before a `git commit`, unless it turns
# pipefail on.
# shortcut: a text match, so a pipe in a quoted string or in an earlier,
# unrelated command is refused too, and a pipefail named in a comment counts;
# parse the command only if agents start tripping on it despite the reason.
set -euo pipefail

# shellcheck source=claude/hooks/command-text.sh
. "$(dirname "${BASH_SOURCE[0]}")/command-text.sh"

commit='git[^|;&]*[[:space:]]commit([[:space:]]|$)'
[[ $text =~ $commit ]] || exit 0
before=${text%%"${BASH_REMATCH[0]}"*}
before=${before//'||'/}
before=${before//'>|'/}
case $before in *'|'*) ;; *) exit 0 ;; esac
pipefail='(^|[;&[:space:]])set[[:space:]]([^;&|]*[[:space:]])?-[[:alpha:]]*o[[:space:]]+pipefail'
if [[ $text =~ $pipefail ]] && [[ $text != *'+o pipefail'* ]]; then exit 0; fi

jq -n --arg reason "A pipe comes before this git commit, and a pipeline reports only its last command's status: a failing check piped into grep or tail would not stop the commit. Run the check on its own (output to a file, then read the file) and chain the commit to that, or start the command with set -o pipefail." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
