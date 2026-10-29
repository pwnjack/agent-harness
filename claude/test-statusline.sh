#!/usr/bin/env bash
# The status line reports to the herdr sidebar without changing what it prints.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
cat > "$tmp/bin/herdr" <<EOS
#!/usr/bin/env bash
line=\$1; shift
for arg in "\$@"; do line="\$line|\$arg"; done
printf '%s\n' "\$line" >> '$tmp/calls'
if [ "\${HERDR_STUB_HANG:-}" = 1 ]; then exec sleep 30; fi
printf 'claude: current\ncodex: current\n'
EOS
chmod +x -- "$tmp"/bin/*
export PATH="$tmp/bin:$PATH"
unset HERDR_CONFIG_PATH HERDR_PANE_ID HERDR_SOCKET_PATH HARNESS_ROLE HARNESS_SIDEBAR_SYNC HERDR_STUB_HANG
export GIT_CEILING_DIRECTORIES="$tmp"
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
statusline="$here/statusline.sh"
: > "$tmp/calls"

# wait_for <text>: poll up to 3 s for a recorded call containing the text.
wait_for() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    grep -qF -- "$1" "$tmp/calls" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

mkdir -p -- "$tmp/proj"
input=$(jq -n --arg d "$tmp/proj" '{model:{display_name:"Opus 5.5 (1M context)"},effort:{level:"high"},workspace:{current_dir:$d},context_window:{used_percentage:12}}')

plain=$(bash "$statusline" <<<"$input")
export HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$tmp/herdr.sock"
reported=$(bash "$statusline" <<<"$input")
if [ -n "$plain" ] && [ "$plain" = "$reported" ]; then ok "status line unchanged with reporting"
else no "status line unchanged with reporting"; fi

if wait_for 'model=Opus 5.5|--token|effort=▰▰▰▱▱ high' && grep -qF -- "repo=proj" "$tmp/calls"; then
  ok "reporter called with cwd, model, effort"
else no "reporter called with cwd, model, effort"; cat "$tmp/calls"; fi

: > "$tmp/calls"; rm -rf -- "$XDG_STATE_HOME/harness"; mkdir -p -- "$tmp/fallback"
fallback=$(jq -n --arg d "$tmp/fallback" '{model:{display_name:"Opus 5.5"},effort:{level:"low"},cwd:$d}')
bash "$statusline" <<<"$fallback" >/dev/null
if wait_for 'repo=fallback'; then ok "cwd falls back to .cwd"
else no "cwd falls back to .cwd"; cat "$tmp/calls"; fi

: > "$tmp/calls"; rm -rf -- "$XDG_STATE_HOME/harness"
start=$(jq -n now)
HERDR_STUB_HANG=1 bash "$statusline" <<<"$input" >/dev/null
elapsed=$(jq -n --argjson s "$start" 'now - $s')
if jq -en --argjson e "$elapsed" '$e <= 1' >/dev/null; then ok "hung herdr: status line prints within 1 s"
else no "hung herdr: status line prints within 1 s (took ${elapsed} s)"; fi

exit "$fail"
