#!/usr/bin/env bash
# Sourced by the Bash guards (pkill-guard.sh, commit-pipe-guard.sh). Reads the
# PreToolUse JSON on stdin and sets `text` to the command with heredoc bodies
# dropped and backslash-newlines joined. Without a command string it exits 0,
# so the hook that sources it stays silent.

command=$(jq -r '.tool_input.command | strings' 2>/dev/null) || exit 0
[ -n "$command" ] || exit 0

# Drop heredoc bodies: lines after <<WORD (or <<-WORD; WORD bare, quoted or
# backslashed) up to a line that is exactly WORD, after leading tabs for <<-.
# A here-string (<<<) starts no body. Known limits: one heredoc per line; a
# << inside quotes or a comment is taken for one; a quoted WORD holding spaces
# or ; | & < > ( ) is cut short, so its body never ends.
text=''
delim=''
strip=''
heredoc='(^|[^<])<<(-?)[[:space:]]*["'"'"'\\]?([^[:space:]"'"'"'\\;|&<>()]+)'
while IFS= read -r line || [ -n "$line" ]; do
  if [ -n "$delim" ]; then
    [ -n "$strip" ] && line=${line#"${line%%[!$'\t']*}"}
    [ "$line" = "$delim" ] && delim=''
    continue
  fi
  if [[ $line =~ $heredoc ]]; then
    strip=${BASH_REMATCH[2]}
    delim=${BASH_REMATCH[3]}
  fi
  text+="$line"$'\n'
done <<< "$command"

text=${text//$'\\\n'/ }
