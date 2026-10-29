#!/usr/bin/env bash
# The Codex sidebar hook reports the session, and apply-hooks.sh merges it
# into hooks.json beside Herdr's own entry.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
cat > "$tmp/bin/herdr" <<STUB
#!/usr/bin/env bash
line=\$1; shift
for arg in "\$@"; do line="\$line|\$arg"; done
printf '%s\n' "\$line" >> '$tmp/calls'
printf 'claude: current\ncodex: current\n'
STUB
chmod +x -- "$tmp"/bin/*
export PATH="$tmp/bin:$PATH"
unset HERDR_CONFIG_PATH HERDR_PANE_ID HERDR_SOCKET_PATH HARNESS_ROLE HARNESS_SIDEBAR_SYNC
export GIT_CEILING_DIRECTORIES="$tmp"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
hook="$here/hooks/sidebar.sh"
export HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$tmp/herdr.sock"

fresh() { : > "$tmp/calls"; rm -rf -- "$XDG_STATE_HOME/harness"; }
last_call() { tail -n 1 -- "$tmp/calls" | sed 's/|--seq|[0-9][0-9]*|/|--seq|N|/'; }
# run_hook <json>: the hook's stdout and stderr land in $tmp/out.
run_hook() { printf '%s' "$1" | bash "$hook" > "$tmp/out" 2>&1; }
# payload <model> <transcript>
payload() { jq -cn --arg m "$1" --arg c "$tmp/my repo" --arg t "$2" \
  '{session_id:"s",transcript_path:$t,cwd:$c,hook_event_name:"SessionStart",model:$m}'; }
prefix='pane|report-metadata|w1:p1|--source|harness:sidebar|--seq|N|--token|repo=my repo|--token|role=orchestrator'

git init -q -- "$tmp/my repo"
transcript="$tmp/my repo/rollout.jsonl"
{
  printf '%s\n' '{"timestamp":"t","type":"session_meta","payload":{"id":"s"}}'
  printf '%s\n' '{"timestamp":"t","type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"high"}}'
  printf '%s\n' '{"timestamp":"t","type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"medium"}}'
  for i in $(seq 1 200); do printf '{"timestamp":"t","type":"response_item","payload":{"n":%s}}\n' "$i"; done
} > "$transcript"

fresh
if run_hook "$(payload gpt-6.1-sol "$transcript")" && [ ! -s "$tmp/out" ] \
   && [ "$(last_call)" = "$prefix|--token|model=Sol 6.1|--token|effort=▰▰▱▱▱ medium" ]; then
  ok "slug formatted"
else no "slug formatted"; last_call; fi

fresh
if run_hook "$(payload some-model "$transcript")" \
   && [ "$(last_call)" = "$prefix|--token|model=some-model|--token|effort=▰▰▱▱▱ medium" ]; then
  ok "unknown slug passed through"
else no "unknown slug passed through"; last_call; fi

fresh
if run_hook "$(payload gpt-6.1-sol "$transcript")" \
   && [ "$(last_call)" = "$prefix|--token|model=Sol 6.1|--token|effort=▰▰▱▱▱ medium" ]; then
  ok "effort from last turn_context"
else no "effort from last turn_context"; last_call; fi

half="$tmp/my repo/half.jsonl"
{
  printf '%s\n' '{"timestamp":"t","type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"low"}}'
  printf '%s' '{"timestamp":"t","type":"turn_context","payload":{"model":"gpt-6.1-s'
} > "$half"
fresh
if run_hook "$(payload gpt-6.1-sol "$half")" \
   && [ "$(last_call)" = "$prefix|--token|model=Sol 6.1|--token|effort=▰▱▱▱▱ low" ]; then
  ok "half-written last line ignored"
else no "half-written last line ignored"; last_call; fi

fresh
if run_hook "$(payload gpt-6.1-sol "$tmp/missing.jsonl")" \
   && [ "$(last_call)" = "$prefix|--token|model=Sol 6.1|--clear-token|effort" ]; then
  ok "no transcript: effort cleared"
else no "no transcript: effort cleared"; last_call; fi

fresh
if run_hook 'not json {' && [ ! -s "$tmp/out" ]; then
  ok "garbage stdin: no output, exit 0"
else no "garbage stdin: no output, exit 0"; cat "$tmp/out"; fi

fresh
if run_hook "$(payload gpt-6.1-sol "$transcript" | jq -c '.hook_event_name="UserPromptSubmit"')" \
   && [ ! -s "$tmp/out" ] && [ -s "$tmp/calls" ]; then
  ok "UserPromptSubmit prints nothing on stdout"
else no "UserPromptSubmit prints nothing on stdout"; cat "$tmp/out"; fi

# --- hooks.json merge ---
cmd="bash '$HOME/.claude/harness/codex/hooks/sidebar.sh'"
herdr_cmd="bash '$HOME/.codex/herdr-agent-state.sh' session"
jq -n --arg h "$herdr_cmd" \
  '{hooks:{SessionStart:[{hooks:[{type:"command",command:$h,timeout:10}]}]}}' > "$CODEX_HOME/hooks.json"
if bash "$here/apply-hooks.sh" > "$tmp/merge-output" 2>&1 \
   && jq -e --arg c "$cmd" --arg h "$herdr_cmd" '
        (.hooks.SessionStart | length) == 2
        and .hooks.SessionStart[0].hooks[0].command == $h
        and .hooks.SessionStart[1] == {hooks:[{type:"command",command:$c,timeout:5}]}
        and ([("UserPromptSubmit","PostToolUse","Stop") as $e
              | .hooks[$e] == [{hooks:[{type:"command",command:$c,timeout:5}]}]] | all)' \
        "$CODEX_HOME/hooks.json" >/dev/null \
   && grep -q "added sidebar hooks to $CODEX_HOME/hooks.json" "$tmp/merge-output"; then
  ok "four events added beside herdr's SessionStart"
else no "four events added beside herdr's SessionStart"; cat "$tmp/merge-output"; fi

cp -- "$CODEX_HOME/hooks.json" "$tmp/first.json"
if bash "$here/apply-hooks.sh" > "$tmp/merge-output" 2>&1 \
   && cmp -s -- "$tmp/first.json" "$CODEX_HOME/hooks.json" \
   && grep -qx 'codex: hooks.json already up to date' "$tmp/merge-output"; then
  ok "second merge unchanged"
else no "second merge unchanged"; cat "$tmp/merge-output"; fi

printf '{ not json' > "$CODEX_HOME/hooks.json"
bash "$here/apply-hooks.sh" > "$tmp/merge-output" 2>&1; status=$?
if [ "$status" = 1 ] && [ "$(cat "$CODEX_HOME/hooks.json")" = '{ not json' ] \
   && grep -qx 'codex: hooks.json is not valid JSON; left unchanged' "$tmp/merge-output"; then
  ok "invalid JSON refused, file unchanged, exit 1"
else no "invalid JSON refused, file unchanged, exit 1"; cat "$tmp/merge-output"; fi

rm -f -- "$CODEX_HOME/hooks.json"
if bash "$here/apply-hooks.sh" > "$tmp/merge-output" 2>&1 \
   && jq -e '[.hooks[] | length] == [1,1,1,1]
        and (.hooks | keys) == ["PostToolUse","SessionStart","Stop","UserPromptSubmit"]' \
        "$CODEX_HOME/hooks.json" >/dev/null; then
  ok "missing file created"
else no "missing file created"; cat "$tmp/merge-output"; fi

# --- terminal title ---
printf '[features]\nhooks = true\n' > "$CODEX_HOME/config.toml"
if bash "$here/apply-config.sh" > "$tmp/merge-output" 2>&1 \
   && grep -qx 'terminal_title = \["spinner", "thread-title"\]' "$CODEX_HOME/config.toml"; then
  ok "terminal_title merged"
else no "terminal_title merged"; cat "$tmp/merge-output"; fi

exit "$fail"
