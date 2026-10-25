#!/usr/bin/env bash
# Keep always-loaded instructions small and new shell code portable to macOS.
set -uo pipefail

BUDGET_CLAUDE_GLOBAL=1457
BUDGET_AGENTS_GLOBAL=2094
EXEMPT='claude/statusline.sh claude/hooks/test-agent-guard.sh claude/skills/delegate/pane.sh claude/skills/delegate/test-delegate.sh claude/skills/delegate/test-sdd-brief.sh claude/skills/delegate/sdd-brief.sh'

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin" || exit 1
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command" || exit 1
done
printf '#!/usr/bin/env bash\nprintf "claude: current\\ncodex: current\\n"\n' > "$tmp/bin/herdr" || exit 1
chmod +x -- "$tmp"/bin/* || exit 1
export PATH="$tmp/bin:$PATH"

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
budget "${BUDGET_FILE_CLAUDE:-$repo/claude/CLAUDE.global.md}" "$BUDGET_CLAUDE_GLOBAL" \
  "budget: CLAUDE.global.md <= $BUDGET_CLAUDE_GLOBAL"
budget "$repo/codex/AGENTS.global.md" "$BUDGET_AGENTS_GLOBAL" \
  "budget: AGENTS.global.md <= $BUDGET_AGENTS_GLOBAL"

# This is a textual guard, not a shell parser; diagnostics retain file and line.
pattern='(^|[[:space:];|&()])(sed[[:space:]]+([^;|&]*[[:space:]])?-i|date[[:space:]]+([^;|&]*[[:space:]])?-d|stat[[:space:]]+([^;|&]*[[:space:]])?-c|find[[:space:]]+([^;|&]*[[:space:]])?-printf|chmod[[:space:]]+([^;|&]*[[:space:]])?--reference|basename[[:space:]]+([^;|&]*[[:space:]])?-a|mapfile([[:space:];|&()]|$)|(declare|local)[[:space:]]+([^;|&]*[[:space:]])?-[[:alpha:]]*A)'
portable=true
if git -C "$repo" ls-files -z -- '*.sh' > "$tmp/scripts"; then
  while IFS= read -r -d '' file; do
    case "$file" in
      test-budgets.sh) continue ;;
    esac
    case " $EXEMPT " in
      *" $file "*) continue ;;
    esac
    if grep -nE -- "$pattern" "$repo/$file" > "$tmp/matches"; then
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
