#!/usr/bin/env bash
# Keep always-loaded instructions small and new shell code portable to macOS.
set -uo pipefail

BUDGET_GLOBAL=5200
EXEMPT='claude/statusline.sh claude/hooks/test-agent-guard.sh claude/skills/delegate/pane.sh claude/skills/delegate/test-delegate.sh'

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" || exit 1

fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
budget() {
  local file=$1 limit=$2 label=$3 bytes
  if bytes=$(wc -c < "$file") && [ "$bytes" -le "$limit" ]; then
    ok "$label"
  else
    no "$label"
    printf '  %s: %s bytes (budget %s)\n' "$file" "${bytes:-unreadable}" "$limit"
  fi
}
budget "${BUDGET_FILE_CLAUDE:-$repo/claude/CLAUDE.global.md}" "$BUDGET_GLOBAL" \
  "budget: CLAUDE.global.md <= $BUDGET_GLOBAL"

# This is a textual guard, not a shell parser; diagnostics retain file and line.
# The sed hex-escape arm (an odd run of backslashes before x, so an escaped
# backslash is not one) scans past ; because sed scripts join commands with it.
pattern='(^|[[:space:];|&()])(sed[[:space:]]+([^|&]*[^|&\\])?(\\\\)*\\x[0-9a-fA-F]{2}|sed[[:space:]]+([^;|&]*[[:space:]])?(-[[:alpha:]]*i|--in-place([=[:space:];|&()]|$))|date[[:space:]]+([^;|&]*[[:space:]])?-d|stat[[:space:]]+([^;|&]*[[:space:]])?-c|find[[:space:]]+([^;|&]*[[:space:]])?-printf|chmod[[:space:]]+([^;|&]*[[:space:]])?--reference|basename[[:space:]]+([^;|&]*[[:space:]])?-a|mapfile([[:space:];|&()]|$)|(declare|local)[[:space:]]+([^;|&]*[[:space:]])?-[[:alpha:]]*A)|`'
scan_shell() {
  # Strip shell comments, retaining line numbers and quoted hashes. Only
  # executable backticks count: quoted literals and escaped ones are harmless.
  # Heredoc bodies are not parsed; prose quotes can leak into shell quote state.
  # Scripts with such heredocs belong in EXEMPT.
  awk '
    BEGIN { single = sprintf("%c", 39); quote = "" }
    {
      code = ""; escaped = 0
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (escaped) {
          code = code (c == "`" ? " " : c); escaped = 0; continue
        }
        if (quote == single) {
          if (c == single) quote = ""
          code = code (c == "`" ? " " : c); continue
        }
        if (c == "\\") { code = code c; escaped = 1; continue }
        if (c == single && quote == "") quote = single
        else if (c == "\"") quote = (quote == "" ? "\"" : "")
        else if (c == "#" && quote == "" &&
                 (i == 1 || substr($0, i - 1, 1) ~ /[[:space:];|&()]/)) break
        code = code c
      }
      print code
    }
  ' "$1" > "$tmp/stripped" || return 2
  grep -nE -- "$pattern" "$tmp/stripped"
}
check_portability() {
  local label=$1 expected=$2 result
  cat > "$tmp/fixture.sh"
  scan_shell "$tmp/fixture.sh" > "$tmp/matches"; result=$?
  if [ "$result" = "$expected" ]; then ok "portability fixture: $label"
  else no "portability fixture: $label (exit $result, expected $expected)"; fi
}
check_portability 'sed -ni' 0 <<'SH'
sed -ni 'p' file
SH
check_portability 'sed -Ei' 0 <<'SH'
sed -Ei 's/a/b/' file
SH
check_portability 'sed --in-place' 0 <<'SH'
sed --in-place 's/a/b/' file
SH
check_portability 'sed --in-place with suffix' 0 <<'SH'
sed --in-place=.bak 's/a/b/' file
SH
check_portability 'backtick substitution' 0 <<'SH'
x=`pwd`
SH
check_portability 'backticks inside double quotes' 0 <<'SH'
x="`pwd`"
SH
check_portability 'comments are ignored' 1 <<'SH'
# sed -ni -Ei --in-place; `pwd`; mapfile
printf ok # sed -i; date -d yesterday; `pwd`
SH
check_portability 'literal and escaped backticks' 1 <<'SH'
printf '%s' '`pwd`'
printf '%s' "\`pwd\`"
SH
check_portability 'quoted hash before a command' 0 <<'SH'
printf '%s' '#'; sed -ni 'p' file
SH
check_portability 'portable sed' 1 <<'SH'
sed -nE 's/a/b/p' file
SH
check_portability 'sed hex escape' 0 <<'SH'
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
SH
check_portability 'sed with an ANSI-C quoted escape' 1 <<'SH'
strip() { sed $'s/\e\\[[0-9;]*m//g'; }
SH
check_portability 'hex escape before a pipe into sed' 1 <<'SH'
printf '\x1b' | sed 's/a/b/'
SH
check_portability 'hex escape after ; inside a sed script' 0 <<'SH'
sed -e 's/a/b/;s/\x1b//g' file
SH
check_portability 'escaped backslash before x in sed' 1 <<'SH'
sed 's/\\x1b/literal/' file
SH
for command in 'sed -i x file' 'date -d yesterday' 'stat -c %a file' \
  'find . -printf %p' 'chmod --reference=file other' 'basename -a a b' \
  'mapfile rows' 'declare -A rows' 'local -A rows'; do
  check_portability "$command" 0 <<< "$command"
done

portable=true
if git -C "$repo" ls-files -z -- '*.sh' > "$tmp/scripts"; then
  while IFS= read -r -d '' file; do
    case "$file" in
      test-budgets.sh) continue ;;
    esac
    case " $EXEMPT " in
      *" $file "*) continue ;;
    esac
    if scan_shell "$repo/$file" > "$tmp/matches"; then
      portable=false
      while IFS= read -r match; do
        printf '  %s:%s\n' "$file" "$match"
      done < "$tmp/matches"
    else
      result=$?
      if [ "$result" -ne 1 ]; then portable=false; fi
    fi
  done < "$tmp/scripts"
else
  portable=false
fi
if "$portable"; then ok 'portability: no GNU-only flags outside EXEMPT'
else no 'portability: no GNU-only flags outside EXEMPT'; fi

# The harness describes what exists and how to use it.
# Real dates (20xx-mm-dd) in tracked Markdown are refused.
lean=true
if git -C "$repo" ls-files -z -- '*.md' > "$tmp/docs"; then
  while IFS= read -r -d '' file; do
    if grep -nE -- '(^|[^0-9])20[0-9]{2}-[01][0-9]-[0-3][0-9]([^0-9]|$)' "$repo/$file" > "$tmp/dates"; then
      lean=false
      while IFS= read -r match; do printf '  %s:%s\n' "$file" "$match"; done < "$tmp/dates"
    fi
  done < "$tmp/docs"
else
  lean=false
fi
if "$lean"; then ok 'lean: no dated history in tracked Markdown'
else no 'lean: no dated history in tracked Markdown'; fi

exit "$fail"
