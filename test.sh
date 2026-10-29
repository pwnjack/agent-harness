#!/usr/bin/env bash
# Run every tracked test-*.sh suite; --list prints their paths without running.
set -uo pipefail

list=false
case "$#:${1:-}" in
  0:) ;;
  1:--list) list=true ;;
  *) echo 'usage: ./test.sh [--list]' >&2; exit 2 ;;
esac

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$repo" || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
git ls-files -z -- '*test-*.sh' > "$tmp/suites" || exit 1
if "$list"; then
  while IFS= read -r -d '' suite; do
    printf '%s\n' "$suite"
  done < "$tmp/suites"
  exit 0
fi

# Keep every suite away from machine state, even if it calls setup.sh.
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
unset HERDR_CONFIG_PATH HERDR_PANE_ID HERDR_SOCKET_PATH HARNESS_ROLE HARNESS_SIDEBAR_SYNC
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
while IFS= read -r -d '' suite; do
  if bash -- "$suite" > "$tmp/output" 2>&1; then
    ok "$suite"
  else
    no "$suite"
    cat -- "$tmp/output"
  fi
done < "$tmp/suites"
exit "$fail"
