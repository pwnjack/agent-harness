#!/usr/bin/env bash
# The sidebar reporter sends one complete, ordered, deduplicated token report.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin" "$tmp/nobin"
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
cat > "$tmp/bin/herdr" <<EOF
#!/usr/bin/env bash
line=\$1; shift
for arg in "\$@"; do line="\$line|\$arg"; done
printf '%s\n' "\$line" >> '$tmp/calls'
if [ "\${HERDR_STUB_HANG:-}" = 1 ]; then exec sleep 30; fi
printf 'claude: current\ncodex: current\n'
EOF
chmod +x -- "$tmp"/bin/*
ln -s -- "$(command -v jq)" "$tmp/nobin/jq"
export PATH="$tmp/bin:$PATH"
unset HERDR_CONFIG_PATH HERDR_PANE_ID HERDR_SOCKET_PATH HARNESS_ROLE HARNESS_SIDEBAR_SYNC HERDR_STUB_HANG
export GIT_CEILING_DIRECTORIES="$tmp"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
reporter="$here/sidebar-report.sh"
export HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$tmp/herdr.sock"

# report <cwd> <model> <effort> [family]: a synchronous report, silent and exit 0.
report() {
  local out; out=$(HARNESS_SIDEBAR_SYNC=1 "$BASH" "$reporter" "$1" "$2" "$3" "${4-claude}" 2>&1) && [ -z "$out" ]
}
# fresh: forget earlier calls and the dedupe cache.
fresh() { : > "$tmp/calls"; rm -rf -- "$XDG_STATE_HOME/harness"; }
calls() { wc -l < "$tmp/calls" | tr -d ' '; }
last_call() { tail -n 1 -- "$tmp/calls" | sed 's/|--seq|[0-9][0-9]*|/|--seq|N|/'; }
seq_of() { sed -n "${1}p" -- "$tmp/calls" | sed 's/.*|--seq|\([0-9][0-9]*\)|.*/\1/'; }
claude_icon=$'\xee\xb2\x82' codex_icon=$'\xee\xb2\x81' # Nerd Font cod-claude, cod-openai
prefix='pane|report-metadata|w1:p1|--source|harness:sidebar|--seq|N'
# expect <repo> <role> <model token> <effort token>: the last call, exactly.
expect() { [ "$(calls)" = 1 ] && [ "$(last_call)" = "$prefix|--token|repo=$1|--token|role=$2|$3|$4" ]; }

git init -q -- "$tmp/my repo"
fresh
if report "$tmp/my repo" 'Opus 5.5' xhigh \
   && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" '--token|effort=xhigh'; then
  ok "repo, role, model, effort sent"
else no "repo, role, model, effort sent"; last_call; fi

levels=true
for level in low medium high xhigh max; do
  fresh
  report "$tmp/my repo" 'Opus 5.5' "$level" \
    && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" "--token|effort=$level" \
    || { levels=false; last_call; }
done
if "$levels"; then ok "effort is the bare level"; else no "effort is the bare level"; fi

roles=true
for role in impl review explore fix; do
  fresh
  HARNESS_ROLE=$role report "$tmp/my repo" 'Opus 5.5' low \
    && expect 'my repo' "$role" "--token|model=$claude_icon Opus 5.5" '--token|effort=low' \
    || { roles=false; last_call; }
done
if "$roles"; then ok "role passes impl/review/explore/fix through"; else no "role passes impl/review/explore/fix through"; fi

leads=true
for role in '' bogus implementer orchestrator; do
  fresh
  HARNESS_ROLE=$role report "$tmp/my repo" 'Opus 5.5' low \
    && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" '--token|effort=low' \
    || { leads=false; last_call; }
done
if "$leads"; then ok "no role or an unknown one is lead"; else no "no role or an unknown one is lead"; fi

fresh
if report "$tmp/my repo" 'Codex 6' low codex \
   && expect 'my repo' lead "--token|model=$codex_icon Codex 6" '--token|effort=low'; then
  ok "model carries the codex icon"
else no "model carries the codex icon"; last_call; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' low claude \
   && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" '--token|effort=low'; then
  ok "model carries the claude icon"
else no "model carries the claude icon"; last_call; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' low other \
   && expect 'my repo' lead '--token|model=Opus 5.5' '--token|effort=low'; then
  nofamily=true
else nofamily=false; fi
fresh
if "$nofamily" && report "$tmp/my repo" 'Opus 5.5' low '' \
   && expect 'my repo' lead '--token|model=Opus 5.5' '--token|effort=low'; then
  ok "unknown family: model without icon"
else no "unknown family: model without icon"; last_call; fi

fresh
if report "$tmp/my repo" '' low && expect 'my repo' lead '--clear-token|model' '--token|effort=low'; then
  ok "empty model clears model"
else no "empty model clears model"; last_call; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' turbo && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" '--clear-token|effort'; then
  ok "invalid effort clears effort"
else no "invalid effort clears effort"; last_call; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' '' && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" '--clear-token|effort'; then
  ok "empty effort clears effort"
else no "empty effort clears effort"; last_call; fi

long=$(printf 'm%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)
long="$long$long$long$long$long"
full="$claude_icon $long"
fresh
if report "$tmp/my repo" "$long" low \
   && expect 'my repo' lead "--token|model=${full:0:80}" '--token|effort=low'; then
  ok "model cut to 80 characters"
else no "model cut to 80 characters"; last_call; fi

git init -q -- "$tmp/main-repo"
git -C "$tmp/main-repo" commit -q --allow-empty -m init
git -C "$tmp/main-repo" worktree add -q -- "$tmp/feature-wt" 2>/dev/null
fresh
if report "$tmp/feature-wt" 'Opus 5.5' low && expect main-repo lead "--token|model=$claude_icon Opus 5.5" '--token|effort=low'; then
  ok "linked worktree reports main repo"
else no "linked worktree reports main repo"; last_call; fi

git clone -q --bare -- "$tmp/main-repo" "$tmp/proj.git"
git -C "$tmp/proj.git" worktree add -q -- "$tmp/bare-wt" 2>/dev/null
fresh
if report "$tmp/bare-wt" 'Opus 5.5' low && expect proj lead "--token|model=$claude_icon Opus 5.5" '--token|effort=low'; then
  ok "bare repo worktree reports name without .git"
else no "bare repo worktree reports name without .git"; last_call; fi

git init -q -- "$tmp/super"
git -C "$tmp/super" -c protocol.file.allow=always submodule add -q -- "$tmp/main-repo" sub-lib 2>/dev/null
fresh
if report "$tmp/super/sub-lib" 'Opus 5.5' low && expect sub-lib lead "--token|model=$claude_icon Opus 5.5" '--token|effort=low'; then
  ok "submodule reports its own name"
else no "submodule reports its own name"; last_call; fi

mkdir -p -- "$tmp/plain folder"
fresh
if report "$tmp/plain folder" 'Opus 5.5' low && expect 'plain folder' lead "--token|model=$claude_icon Opus 5.5" '--token|effort=low'; then
  ok "outside git uses folder name"
else no "outside git uses folder name"; last_call; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' low && report "$tmp/my repo" 'Opus 5.5' high \
   && [ "$(calls)" = 2 ] && [ -n "$(seq_of 1)" ] && [ "$(seq_of 2)" -gt "$(seq_of 1)" ]; then
  ok "seq increases between calls"
else no "seq increases between calls"; cat -- "$tmp/calls"; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' low && report "$tmp/my repo" 'Opus 5.5' low && [ "$(calls)" = 1 ]; then
  ok "identical second call skipped"
else no "identical second call skipped"; cat -- "$tmp/calls"; fi

for cache in "$XDG_STATE_HOME"/harness/sidebar/*; do
  if [ -f "$cache" ]; then touch -t 200001010000 -- "$cache"; fi
done
if report "$tmp/my repo" 'Opus 5.5' low && [ "$(calls)" = 2 ]; then
  ok "call sent again once cache is old"
else no "call sent again once cache is old"; cat -- "$tmp/calls"; fi

fresh
if report "$tmp/my repo" 'Opus 5.5' low \
   && HERDR_SOCKET_PATH="$tmp/other.sock" report "$tmp/my repo" 'Opus 5.5' low \
   && [ "$(calls)" = 2 ] && [ "$(ls -- "$XDG_STATE_HOME/harness/sidebar" | wc -l | tr -d ' ')" = 2 ]; then
  ok "two sockets, same pane id, separate caches"
else no "two sockets, same pane id, separate caches"; cat -- "$tmp/calls"; fi

fresh
SECONDS=0
if HERDR_STUB_HANG=1 report "$tmp/my repo" 'Opus 5.5' low && [ "$SECONDS" -lt 4 ] && [ "$(calls)" = 1 ]; then
  ok "hung herdr killed, reporter returns within 4 s"
else no "hung herdr killed, reporter returns within 4 s"; fi

fresh
landed=false
if out=$("$BASH" "$reporter" "$tmp/my repo" 'Opus 5.5' max claude 2>&1) && [ -z "$out" ]; then
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if [ -s "$tmp/calls" ]; then landed=true; break; fi
    sleep 0.1
  done
fi
if "$landed" && expect 'my repo' lead "--token|model=$claude_icon Opus 5.5" '--token|effort=max'; then
  ok "detached call lands"
else no "detached call lands"; fi

fresh
if (unset HERDR_PANE_ID; report "$tmp/my repo" 'Opus 5.5' low) && [ "$(calls)" = 0 ]; then
  ok "no pane id: no call, exit 0"
else no "no pane id: no call, exit 0"; fi

fresh
if PATH="$tmp/nobin" report "$tmp/my repo" 'Opus 5.5' low && [ "$(calls)" = 0 ]; then
  ok "no herdr on PATH: no call, exit 0"
else no "no herdr on PATH: no call, exit 0"; fi

exit "$fail"
