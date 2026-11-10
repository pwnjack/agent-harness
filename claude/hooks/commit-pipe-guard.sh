#!/usr/bin/env bash
# PreToolUse hook on Bash. A pipeline reports only its last command's status,
# so `check | tail -5 && git commit` commits when the check fails. This
# refuses a `git commit` chained with && or || after a pipeline, unless
# `set -o pipefail` is in effect by then.
#
# A textual guard, not a shell parser. In order: heredoc bodies are dropped
# and backslash-newlines joined (command-text.sh), quoted strings replaced by
# Q and comments cut off, redirections that hold & or | reduced to > and <, a
# line ending in && || | ( or { joined to the next, the ; or newline before a
# closing } or ) dropped, grouping characters ( ) { } blanked, the rest cut
# into lists at newlines, ; and &. Within a list, a `git commit` in command
# position (bare or after a path, after assignments and wrappers such as sudo
# or env, global options skipped) that follows an element holding a pipe is
# refused.
#
# Known limits. False refusals: a pipe inside $(...) earlier in the chain.
# Not seen: `if check | tail; then git commit; fi`; a commit that is not the
# first command of a group on the right of the chain (`check | tail && { echo
# ready; git commit; }`); a commit inside a quoted `bash -c` string; a command
# or subcommand written in quotes (`"git" commit`). pipefail is one flag for
# the whole command: a `set -o pipefail` inside an earlier subshell counts for
# what follows it, and `set -o "pipefail"` is not recognised.
set -euo pipefail

# shellcheck source=claude/hooks/command-text.sh
. "$(dirname "${BASH_SOURCE[0]}")/command-text.sh"
case $text in *commit*) ;; *) exit 0 ;; esac

# Quoted strings become Q and comments go, leftmost first: an apostrophe in a
# comment opens no string, and a # in a string starts no comment. A backslash
# keeps a double-quoted string open across \".
newline=$'\n'
token="('[^']*'|\"([^\"\\\\]|\\\\.)*\"|(^|[[:space:];&|(])#[^$newline]*)"
while [[ $text =~ $token ]]; do
  match=${BASH_REMATCH[1]}
  case $match in
    "'"* | '"'*) text=${text/"$match"/Q} ;;
    *) text=${text/"$match"/"${BASH_REMATCH[3]}"} ;;
  esac
done

# Redirections and |& lose their & and |, so what is left of those characters
# is a pipe, a list operator or a background &. >& and <& keep a mark (@), so
# `2>&1` stays one word with its target.
text=${text//'>|'/>}
text=${text//'|&'/|}
text=${text//'>&'/>@}
text=${text//'<&'/<@}
text=${text//'&>'/>}

# A line ending in an operator or opening a group continues on the next one.
joiner='(&&|\|\||\||[({])[[:space:]]*'$'\n'
while [[ $text =~ $joiner ]]; do
  text=${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]} "}
done

# The ; or newline that closes a group belongs to the group, not to the list:
# `{ check | tail; } && git commit` is one chain.
closer='[;[:space:]]+([})])'
while [[ $text =~ $closer ]]; do
  text=${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}"}
done

sep=$'\037'
text=${text//'&&'/$sep}
text=${text//'||'/$sep}
text=${text//[(){\}]/ }

# True when the simple command $1 is a `git commit`: git as the command word
# (bare or after a path; after assignments, redirections and !, and anywhere
# after a wrapper such as sudo or env, whose own operands are not parsed), its
# global options and their operands skipped, then the subcommand commit.
is_commit() {
  local words word n i=0 wrapped=0
  read -r -a words <<< "$1" || true
  n=${#words[@]}
  while [ "$i" -lt "$n" ]; do
    word=${words[$i]}
    i=$((i + 1))
    case $word in
      [[:alpha:]_]*=* | '!') continue ;;
      # A redirection: its target is the next word unless one follows the
      # operator in this word.
      [0-9]'>'* | '>'* | [0-9]'<'* | '<'*)
        word=${word#"${word%%[<>]*}"}
        [ -n "${word#"${word%%[!<>]*}"}" ] || i=$((i + 1))
        continue ;;
    esac
    case ${word##*/} in
      git) break ;;
      sudo | env | command | exec | time | nice | nohup | timeout) wrapped=1 ;;
      *) [ "$wrapped" = 1 ] || return 1 ;;
    esac
  done
  while [ "$i" -lt "$n" ]; do
    word=${words[$i]}
    i=$((i + 1))
    case $word in
      -C | -c | --git-dir | --work-tree | --namespace | --config-env) i=$((i + 1)) ;;
      -*) ;;
      commit) return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}

# `set` counts in command position only, and not as one side of a pipe. Its
# options are read in order up to any --: the last -o or +o whose operand is
# the word pipefail wins.
set_command='^[[:space:]]*set[[:space:]]'
unsafe=0
pipefail=0
while IFS= read -r list; do
  piped=0
  rest=$list$sep
  while [ -n "$rest" ]; do
    element=${rest%%"$sep"*}
    rest=${rest#*"$sep"}
    case $element in
      *'|'*) ;;
      *)
        if [[ $element =~ $set_command ]]; then
          read -r -a options <<< "$element" || true
          j=1
          while [ "$j" -lt "${#options[@]}" ]; do
            option=${options[$j]}
            j=$((j + 1))
            [ "$option" = -- ] && break
            [ "${options[$j]:-}" = pipefail ] || continue
            case $option in
              +o) pipefail=0 ;;
              -o | -[[:alpha:]]*o) pipefail=1 ;;
            esac
          done
        fi
        ;;
    esac
    if [ "$piped" = 1 ] && is_commit "${element%%|*}"; then
      unsafe=1
      break 2
    fi
    case $element in *'|'*) [ "$pipefail" = 1 ] || piped=1 ;; esac
  done
done <<< "${text//[;&]/$'\n'}"
[ "$unsafe" = 1 ] || exit 0

jq -n --arg reason "This git commit is chained after a pipeline, and a pipeline reports only its last command's status: a failing check piped into grep or tail would not stop the commit. Run the check on its own (output to a file, then read the file) and chain the commit to that, or start the command with set -o pipefail." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
