#!/usr/bin/env bash
# Integrity checks for the tracked agent harness: skill frontmatter, files the
# skills and global instructions name, the "no pinned model id" rule, and that
# every listed plugin has a registered marketplace. Uses disposable repositories;
# never touches Herdr, Codex or a live ~/.claude.
#   bash claude/skills/test-skills.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude=$(dirname "$here")
tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
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

check() { # check <description> <command...>
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi
}

# shellcheck disable=SC2088
check 'compound-learning: named audit script exists' \
  bash -c 'grep -q "~/.claude/harness/brain/audit.sh" "$1" && test -f "$2/brain/audit.sh"' \
  _ "$here/compound-learning/SKILL.md" "$(dirname "$claude")"

# Execute the skill's example, with a recording audit in a disposable HOME.
awk '/^   ```bash$/ { code=1; next } /^   ```$/ { code=0 } code { sub(/^   /, ""); print }' \
  "$here/compound-learning/SKILL.md" > "$tmp/example.sh"
check 'compound-learning: runnable audit example exists' test -s "$tmp/example.sh"
check 'compound-learning: destination and report use per lesson consistently' \
  bash -c 'grep -q "per lesson" "$1" && ! grep -q "per mistake" "$1"' \
  _ "$here/compound-learning/SKILL.md"
mkdir -p -- "$HOME/.claude/harness/brain" "$tmp/repo.with_punctuation/sub/dir"
cat > "$HOME/.claude/harness/brain/audit.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$HOME/audit-args"
if [ ! -d "$1/$2/memory" ]; then
  printf 'audit error: missing memory directory\n' >&2
  exit 1
fi
exit "${TEST_AUDIT_RESULT:-0}"
SH
git init -q -b main -- "$tmp/repo.with_punctuation" || exit 1
root=$(cd -- "$tmp/repo.with_punctuation" && pwd -P)
expected_key=$(printf '%s' "$root" | LC_ALL=C tr -c '[:alnum:]' '-')
mkdir -p -- "$CLAUDE_CONFIG_DIR/projects/$expected_key/memory"
for brain_state in absent default xdg; do
  rm -rf -- "$HOME/.local/state/agent-brain.git" "$XDG_STATE_HOME/agent-brain.git"
  rm -f -- "$HOME/audit-args"
  case "$brain_state" in
    default) mkdir -p -- "$HOME/.local/state/agent-brain.git" ;;
    xdg) mkdir -p -- "$XDG_STATE_HOME/agent-brain.git" ;;
  esac
  result=0
  (
    if [ "$brain_state" != xdg ]; then unset XDG_STATE_HOME; fi
    cd -- "$root/sub/dir" || exit 1
    bash "$tmp/example.sh"
  ) > "$tmp/example-output" 2>&1 || result=$?
  if [ "$brain_state" = absent ]; then
    if [ "$result" -eq 0 ] && [ ! -e "$HOME/audit-args" ]; then
      ok 'compound-learning: absent brain skips the audit'
    else no 'compound-learning: absent brain skips the audit'; fi
  elif [ "$result" -eq 0 ] && [ -f "$HOME/audit-args" ] \
       && [ "$(cat -- "$HOME/audit-args")" = "$CLAUDE_CONFIG_DIR/projects
$expected_key" ]; then
    ok "compound-learning: $brain_state brain audits the repository root from a subdirectory"
  else no "compound-learning: $brain_state brain audits the repository root from a subdirectory"; fi
done
git -C "$root" -c user.name=Test -c user.email=test@example.org commit -q --allow-empty -m fixture || exit 1
git -C "$root" worktree add -q --detach -- "$tmp/linked-worktree" || exit 1
mkdir -p -- "$tmp/linked-worktree/sub/dir"
rm -f -- "$HOME/audit-args"
result=0
(cd -- "$tmp/linked-worktree/sub/dir" && bash "$tmp/example.sh") > "$tmp/example-output" 2>&1 || result=$?
if [ "$result" -eq 0 ] && [ -f "$HOME/audit-args" ] \
   && [ "$(cat -- "$HOME/audit-args")" = "$CLAUDE_CONFIG_DIR/projects
$expected_key" ]; then
  ok 'compound-learning: linked worktree audits the main checkout memory'
else no 'compound-learning: linked worktree audits the main checkout memory'; fi

mkdir -p -- "$tmp/new-project"
rm -f -- "$HOME/audit-args"
result=0
(cd -- "$tmp/new-project" && bash "$tmp/example.sh") > "$tmp/example-output" 2>&1 || result=$?
if [ "$result" -eq 0 ] && [ ! -e "$HOME/audit-args" ] && [ ! -s "$tmp/example-output" ]; then
  ok 'compound-learning: absent memory skips the audit without an error'
else no 'compound-learning: absent memory skips the audit without an error'; fi

outside_root=$(cd -- "$tmp/new-project" && pwd -P)
outside_key=$(printf '%s' "$outside_root" | LC_ALL=C tr -c '[:alnum:]' '-')
mkdir -p -- "$CLAUDE_CONFIG_DIR/projects/$outside_key/memory"
result=0
(cd -- "$tmp/new-project" && bash "$tmp/example.sh") > "$tmp/example-output" 2>&1 || result=$?
if [ "$result" -eq 0 ] && [ -f "$HOME/audit-args" ] \
   && [ "$(cat -- "$HOME/audit-args")" = "$CLAUDE_CONFIG_DIR/projects
$outside_key" ]; then
  ok 'compound-learning: outside Git audits the physical project directory'
else no 'compound-learning: outside Git audits the physical project directory'; fi

export TEST_AUDIT_RESULT=19
result=0
(cd -- "$root/sub/dir" && bash "$tmp/example.sh") > "$tmp/example-output" 2>&1 || result=$?
unset TEST_AUDIT_RESULT
if [ "$result" -eq 19 ]; then ok 'compound-learning: audit failure is propagated'
else no 'compound-learning: audit failure is propagated'; fi

# --- every skill directory has a SKILL.md whose name is the directory name ----
for d in "$here"/*/; do
  d=${d%/} n=$(basename "$d") f="$d/SKILL.md"
  check "$n: SKILL.md exists" test -f "$f"
  [ -f "$f" ] || continue
  check "$n: frontmatter name matches directory" \
    bash -c 'sed -n "2p" "$1" | grep -qx "name: $2"' _ "$f" "$n"
  check "$n: has a description" bash -c 'sed -n "3p" "$1" | grep -q "^description: ."' _ "$f"
done

# --- every skill file the instructions name exists in the repo, under the
# fixed harness link (~/.claude/harness/claude/skills/) or the skills link ---
missing=0
# shellcheck disable=SC2088  # a literal ~ path, matched as text
while IFS= read -r ref; do
  [ -e "$here/$ref" ] || { no "skills/$ref is referenced but missing"; missing=1; }
done < <(grep -rhoE '~/\.claude/(harness/claude/)?skills/[A-Za-z0-9._/-]+' "$here" "$claude/CLAUDE.global.md" \
           --include='*.md' --include='*.sh' | sed -E 's#^~/\.claude/(harness/claude/)?skills/##' | sort -u)
[ "$missing" = 0 ] && ok "every referenced skill file exists" || fail=1
for skill in delegate compound-learning wrap-up handover; do
  check "global instructions name the $skill skill, and it exists" \
    bash -c 'grep -q "\`$2\` skill" "$1" && test -f "$3/$2/SKILL.md"' _ "$claude/CLAUDE.global.md" "$skill" "$here"
done

# --- only the orchestrator in the main checkout runs the memory-writing skills
for skill in compound-learning wrap-up handover; do
  check "$skill: runs only as the orchestrator in the main checkout" \
    bash -c 'tr "\n" " " < "$1" | grep -q "orchestrator in the main checkout"' _ "$here/$skill/SKILL.md"
done

# --- session end: wrap-up records through handover, handover has its parts ---
check "wrap-up: names the handover and compound-learning skills" \
  bash -c 'grep -q "\`handover\` skill" "$1" && grep -q "\`compound-learning\` skill" "$1"' \
  _ "$here/wrap-up/SKILL.md"
check "wrap-up: never pkill -f, and only this session's items" \
  bash -c 'grep -q "Never \`pkill -f\`" "$1" && grep -q "only what this session made" "$1"' \
  _ "$here/wrap-up/SKILL.md"
check "handover: the six parts in order" \
  bash -c 'printf "%s\n" State "Shipped this session" Decisions Next Leftovers "Pending from the user" > "$2/parts"
    grep -oE "^[1-6]\. \*\*[^.]+\.\*\*" "$1" | sed -E "s/^[1-6]\. \*\*(.*)\.\*\*$/\1/" | cmp -s - "$2/parts"' \
  _ "$here/handover/SKILL.md" "$tmp"

# --- the review rubric the delegate skill hands to every reviewer --------------
# shellcheck disable=SC2088  # a literal ~ path, matched as text
check "delegate: the review brief names the rubric under the harness link" \
  grep -q '~/\.claude/harness/claude/skills/delegate/review\.md' "$here/delegate/SKILL.md"
check "delegate: launches name pane.sh under the harness link" \
  bash -c 'grep -q "~/\.claude/harness/claude/skills/delegate/pane\.sh" "$1" && ! grep -q "~/\.claude/skills/" "$1"' \
  _ "$here/delegate/SKILL.md"
check "delegate: the rubric is report-only" grep -q 'edit no file' "$here/delegate/review.md"

# --- no pinned model identifiers in instruction text ---------
check "no pinned model ids in skill or instruction text" \
  bash -c '! grep -rEq "claude-(opus|sonnet|haiku|fable)-[0-9]|gpt-[0-9]" "$1" "$2" --include="*.md"' \
  _ "$here" "$claude/CLAUDE.global.md"

# --- settings: valid JSON, and no listed plugin without its marketplace --------
# Built-in marketplaces ship with Claude Code and never appear in
# extraKnownMarketplaces.
settings="$claude/settings.json"
builtin_marketplaces="anthropic-plugin-directory"
check "settings.json is valid JSON" jq -e . "$settings"
orphans=$(jq -r --arg builtin "$builtin_marketplaces" \
  '((.extraKnownMarketplaces // {} | keys) + ($builtin | split(" "))) as $m
  | (.enabledPlugins // {}) | keys[] | select((split("@")[1]) as $mk | ($m | index($mk)) == null)' "$settings" 2>/dev/null)
if [ -z "$orphans" ]; then ok "every listed plugin has a registered marketplace"
else no "plugin without a marketplace: $orphans"; fi

exit "$fail"
