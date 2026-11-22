#!/usr/bin/env bash
# Integrity checks for the tracked agent harness: skill frontmatter, files the
# skills and global instructions name, the hand-overs between skills and the
# "no pinned model id" rule. Never touches Herdr, Codex or a live ~/.claude.
#   bash claude/skills/test-skills.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude=$(dirname "$here")
repo=$(dirname "$claude")
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
for skill in learn handover; do
  check "$skill: names the audit script, and it exists" \
    bash -c 'grep -q "~/.claude/harness/brain/audit.sh --here" "$1" && test -f "$2/brain/audit.sh"' \
    _ "$here/$skill/SKILL.md" "$repo"
done

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
# The loop in the global instructions is how a skill gets reached.
for d in "$here"/*/; do
  skill=$(basename "$d")
  check "global instructions name the $skill skill" grep -qF -- "\`$skill\`" "$claude/CLAUDE.global.md"
done
# Each skill hands over to one that exists.
for pair in design:grill design:write-plan write-plan:build build:delegate build:review review:delegate \
            review:wrap-up wrap-up:handover wrap-up:learn handover:learn learn:review; do
  check "${pair%:*}: names the ${pair#*:} skill" grep -qF -- "\`${pair#*:}\` skill" "$here/${pair%:*}/SKILL.md"
done
# --- one entry rule: the global instructions route work to the lightest step
# that fits, each skill repeats its side, and wrap-up stays outside the loop --
# says <file> <text>: the file holds the text, line breaks and space runs aside
says() { tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF -- "$2"; }
g=$claude/CLAUDE.global.md
check "loop: work enters at the first entry that fits, lightest first" \
  says "$g" 'Work enters at the first of these that fits; each skill ends by naming the next. - Trivial (a one-line fix, a rename, a config tweak): no loop. Do it, verify it. - Small (a bug fix, a contained change): `build`. - Decided, but more than three lines of scope: `write-plan`. - Anything else (more than one sound approach, real rework if you guess wrong): `design`.'
check "loop: its last step is review" \
  grep -qxF -- '`design` (brainstorm, `grill`, spec) → `write-plan` → `build` → `review`' "$g"
check "loop: wrap-up closes a session, not a change" \
  says "$g" 'run the `wrap-up` skill: it closes a session, not a change'
check "design: its description claims only an open, costly approach" \
  bash -c 'sed -n 3p "$1" | grep -qF "more than one sound approach, would cost real rework if guessed wrong, and has no spec yet" \
    && ! sed -n 3p "$1" | grep -qF "build X"' _ "$here/design/SKILL.md"
check "verification: a step is run as the user will, or marked untested" \
  says "$g" 'Run steps as the user will or mark them untested.'
check "design: sends a decided change on" \
  says "$here/design/SKILL.md" 'A change that is already decided needs no spec'
check "design: an early yes skips the questions, not the attack list" \
  says "$here/design/SKILL.md" 'An early yes ("build it") skips the questions to the user, not the attack list: answer it from the code and put what stays open in the spec.'
check "write-plan: plans a decided change that has no spec" \
  says "$here/write-plan/SKILL.md" 'No spec, because nothing was left to design: write the plan alone'
check "write-plan: sends a three-line scope to build" \
  says "$here/write-plan/SKILL.md" 'A scope that fits in three lines needs no plan: the `build` skill.'
check "build: a three-line scope is the plan and the acceptance" \
  says "$here/build/SKILL.md" 'the request is the plan when its scope fits in three lines: say them (what changes, where, how it is checked) and start. They stand in for the plan and for the spec'
check "build: an unknown cause is found first" \
  says "$here/build/SKILL.md" 'A bug whose cause is not known: find the cause before the three lines.'
check "build: an open detail is named, and asked only when it cannot be undone" \
  says "$here/build/SKILL.md" 'take the smallest reading and name it in those lines. Ask first only when a wrong guess cannot be undone.'
check "build: sends bigger or undecided work back" \
  says "$here/build/SKILL.md" 'More than three lines: the `write-plan` skill first. More than one sound approach and real rework if you guess wrong: the `design` skill first.'
check "build: does not hand over to wrap-up" \
  says "$here/build/SKILL.md" 'or the next change. The `wrap-up` skill waits for the session'
check "review: does not hand over to wrap-up inside a session" \
  says "$here/review/SKILL.md" 'or the next change. At the session'
check "review: the brief carries the scope lines when there is no file" \
  says "$here/review/SKILL.md" 'with no file, the three scope lines from the `build` skill, written out'
check "global: the skipped-and-risk footer ends reports of work or findings" \
  says "$g" 'End a report of work or findings with one or two lines'
check "wrap-up: a session that made nothing skips inventory, cleanup and confirmation" \
  says "$here/wrap-up/SKILL.md" 'A session that changed nothing and started nothing (no edit, commit, pane, server, worktree or branch) skips steps 2 to 4. A resumed or compacted session cannot know that, and skips none.'
check "delegate: an explore brief is the first line and the question" \
  says "$here/delegate/SKILL.md" 'A read-only `explore` brief needs only the first line, the question and where to look.'

# --- only the orchestrator in the main checkout runs the memory-writing skills
for skill in learn wrap-up handover; do
  check "$skill: runs only as the orchestrator in the main checkout" \
    bash -c 'tr "\n" " " < "$1" | grep -q "orchestrator in the main checkout"' _ "$here/$skill/SKILL.md"
done

# --- session end: wrap-up records through handover, handover has its parts ---
check "wrap-up: never pkill -f, and only this session's items" \
  bash -c 'grep -q "Never \`pkill -f\`" "$1" && grep -q "only what this session made" "$1"' \
  _ "$here/wrap-up/SKILL.md"
check "wrap-up: deletes only branches this session created" \
  bash -c 'grep -q "only branches this session created" "$1" && tr "\n" " " < "$1" | tr -s " " | grep -q "each merged branch it created"' \
  _ "$here/wrap-up/SKILL.md"
check "handover: the five parts in order" \
  bash -c 'printf "%s\n" State Decisions Next Leftovers "Pending from the user" > "$2/parts"
    grep -oE "^[1-5]\. \*\*[^.]+\.\*\*" "$1" | sed -E "s/^[1-5]\. \*\*(.*)\.\*\*$/\1/" | cmp -s - "$2/parts"' \
  _ "$here/handover/SKILL.md" "$tmp"
check "handover: a leftover says where it lives" \
  bash -c 'tr "\n" " " < "$1" | tr -s " " | grep -q "untested paths, each with the file, function or screen it lives in\."' \
  _ "$here/handover/SKILL.md"

# --- the review rubric the delegate skill hands to every reviewer --------------
# shellcheck disable=SC2088  # a literal ~ path, matched as text
check "review: the brief names the rubric under the harness link" \
  grep -q '~/\.claude/harness/claude/skills/review/rubric\.md' "$here/review/SKILL.md"
check "delegate: launches name pane.sh under the harness link" \
  bash -c 'grep -q "~/\.claude/harness/claude/skills/delegate/pane\.sh" "$1" && ! grep -q "~/\.claude/skills/" "$1"' \
  _ "$here/delegate/SKILL.md"
check "review: the rubric is report-only" grep -q 'edit no file' "$here/review/rubric.md"
check "review: the rubric keeps the reviewer to the commands its brief names" \
  grep -q 'Run only the commands the brief names' "$here/review/rubric.md"
check "review: the brief names the checks the reviewer may run" \
  says "$here/review/SKILL.md" 'the checks the reviewer may run'

# --- no pinned model identifiers in instruction text ---------
check "no pinned model ids in skill, instruction or manual text" \
  bash -c '! grep -rEq "claude-(opus|sonnet|haiku|fable)-[0-9]|gpt-[0-9]" "$1" "$2" "$3" --include="*.md"' \
  _ "$here" "$claude/CLAUDE.global.md" "$repo/docs/internals"

check "settings.json is valid JSON" jq -e . "$claude/settings.json"

exit "$fail"
