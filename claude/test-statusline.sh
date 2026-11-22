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

if wait_for $'model=\xee\xb2\x82 Opus 5.5|--token|effort=high' && grep -qF -- "repo=proj" "$tmp/calls"; then
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

# Prompt cache and weekly pace, read from the status JSON alone.
strip() { sed $'s/\e\\[[0-9;]*m//g'; }   # a literal ESC: BSD sed has no \x1b
now=$(date +%s)
FIRE=$'\xf3\xb0\x88\xb8' SNOW=$'\xf3\xb0\x9c\x97'
base=$(jq -n --arg d "$tmp/proj" --argjson n "$now" '{model:{display_name:"Opus 5.5"},workspace:{current_dir:$d},
  rate_limits:{seven_day:{used_percentage:44,resets_at:($n+302400)}}}')
line() { jq "$@" <<<"$base" | bash "$statusline" | strip; }

out=$(line --argjson n "$now" '.prompt_cache={caching_observed:true,warm:true,expires_at:($n+2550),recache_tokens_if_cold:174945}')
case $out in *"│ $FIRE 42m │"*) ok "warm cache: flame with the time left";; *) no "warm cache: flame with the time left: $out";; esac
out=$(line '.prompt_cache={caching_observed:true,warm:false,expires_at:null,recache_tokens_if_cold:174945}')
case $out in *"│ $SNOW 175k │"*) ok "cold cache: snowflake with the tokens to re-cache";; *) no "cold cache: snowflake with the tokens to re-cache: $out";; esac
out=$(line '.prompt_cache={caching_observed:true,warm:false,expires_at:null,recache_tokens_if_cold:null}')
case $out in *"│ $SNOW │"*) ok "cold cache after a compaction: snowflake alone";; *) no "cold cache after a compaction: snowflake alone: $out";; esac
out=$(line --argjson n "$now" '.prompt_cache={caching_observed:true,warm:true,expires_at:($n-30),recache_tokens_if_cold:174945}')
case $out in *"│ $SNOW 175k │"*) ok "warm flag with a past expiry renders cold";; *) no "warm flag with a past expiry renders cold: $out";; esac
out=$(line '.prompt_cache={caching_observed:false,warm:false,expires_at:null}')
case $out in *"$FIRE"*|*"$SNOW"*) no "caching not observed: no cache segment: $out";; *) ok "caching not observed: no cache segment";; esac
out=$(line '.')
case $out in *"$FIRE"*|*"$SNOW"*) no "no prompt_cache block: no cache segment: $out";; *) ok "no prompt_cache block: no cache segment";; esac

# 44 % used with half the week gone: six points behind the clock.
case $out in *"44% -6 · "*) ok "weekly pace: used minus elapsed, before the reset";; *) no "weekly pace: used minus elapsed, before the reset: $out";; esac
out=$(line --argjson n "$now" '.rate_limits.seven_day={used_percentage:75,resets_at:($n+302400)}')
case $out in *"75% +25 · "*) ok "weekly pace ahead of the clock is signed";; *) no "weekly pace ahead of the clock is signed: $out";; esac
out=$(line --argjson n "$now" '.rate_limits.seven_day={used_percentage:49.8,resets_at:($n+302400)}')
case $out in *"50% +0 · "*) ok "weekly pace within half a point prints +0";; *) no "weekly pace within half a point prints +0: $out";; esac
# A reset already behind us counts as a full week elapsed; one more than a
# week away as none.
out=$(line --argjson n "$now" '.rate_limits.seven_day={used_percentage:44,resets_at:($n-86400)}')
case $out in *"44% -56 · "*) ok "weekly pace clamps a past reset to a full week";; *) no "weekly pace clamps a past reset to a full week: $out";; esac
out=$(line --argjson n "$now" '.rate_limits.seven_day={used_percentage:44,resets_at:($n+691200)}')
case $out in *"44% +44 · "*) ok "weekly pace clamps a far reset to nothing elapsed";; *) no "weekly pace clamps a far reset to nothing elapsed: $out";; esac
out=$(line '.rate_limits.seven_day={used_percentage:44}')
case $out in *"44% -"*|*"44% +"*) no "weekly pace needs the reset time: $out";; *"7d"*"44%"*) ok "weekly pace needs the reset time";; *) no "weekly pace needs the reset time: $out";; esac

exit "$fail"
