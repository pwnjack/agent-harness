#!/usr/bin/env bash
# Fixture tests for codex-model.sh, and for pane.sh's opt-in gate and verdicts
# against a stub herdr. Synthetic catalogues only; never touches the real
# Herdr, Codex or Claude.
#   bash claude/skills/delegate/test-delegate.sh
set -uo pipefail
here=$(dirname "$(readlink -f "$0")")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

# model <slug> <visibility> <priority> <efforts...>
model() {
  local slug=$1 vis=$2 pri=$3; shift 3
  jq -n --arg s "$slug" --arg v "$vis" --argjson p "$pri" \
    '{slug:$s, visibility:$v, priority:$p,
      supported_reasoning_levels: ($ARGS.positional | map({effort: ., description: "x"}))}' --args "$@"
}
catalogue() { jq -s '{models: .}' > "$tmp/$1.json"; }

all=(low medium high xhigh max ultra)
# Shaped like the real catalogue: a newer generation, an older one that still
# carries a codename the newer lacks, a codename-less legacy slug, a hidden row.
{ model gen9-astra list 1 "${all[@]}"; model gen9-sol list 2 "${all[@]}"; model gen9-luna list 3 low medium high
  model gen9-reserve hide 3 "${all[@]}"; model gen8.5-sol list 4 "${all[@]}"; model gen8.5-terra list 7 "${all[@]}"
  model gen8.5-luna list 8 "${all[@]}"; model gen8 list 12 low medium high xhigh; } | catalogue real
# Newest by version, not by priority; plain slug beats variants and snapshots.
{ model gen10-sol-mini list 5 "${all[@]}"; model gen10-sol-2031-01-01 list 4 "${all[@]}"
  model gen10-sol list 6 "${all[@]}"; model gen9-sol list 1 "${all[@]}"; model gen10-nova list 0 "${all[@]}"
  model gen9-astra list 2 "${all[@]}"; } | catalogue newer
# Only a variant exists in the newest generation.
{ model gen10-sol-mini list 3 "${all[@]}"; model gen9-sol list 1 "${all[@]}"; } | catalogue variant
# Effort shapes: only higher levels, none listed, plain strings, unknown names.
{ model gen9-sol list 1 high xhigh; model gen9-luna list 2 max ultra; model gen9-terra list 3 extra-high medium
  jq -n '{slug:"gen9-mars", visibility:"list", priority:4}'
  jq -n '{slug:"gen9-vega", visibility:"list", priority:5, supported_reasoning_levels:["low","medium"]}'
  model gen9-orion list 6 low high; } | catalogue efforts
{ model gen9-sol hide 1 "${all[@]}"; } | catalogue nolisted
# A new generation that ranks sol first must not gate sol.
{ model gen10-sol list 1 "${all[@]}"; model gen9-astra list 2 "${all[@]}"; model gen9-sol list 3 "${all[@]}"; } | catalogue solfirst
echo '[]' > "$tmp/arr.json"
echo '{not json' > "$tmp/broken.json"

# expect <catalogue> <alias> <effort> <want-exit> <want-stdout-joined>
expect() {
  local out rc
  out=$(CODEX_MODELS_CACHE="$tmp/$1.json" "$here/codex-model.sh" "$2" "$3" 2>/dev/null); rc=$?
  out=$(paste -sd' ' <<<"$out")
  if [ "$rc" = "$4" ] && [ "$out" = "$5" ]; then echo "ok   $1 $2 $3"
  else echo "FAIL $1 $2 $3: exit $rc want $4, out '$out' want '$5'"; fail=1; fi
}

expect real  sol      medium 0 "gen9-sol medium"      # newest generation wins
expect real  luna     xhigh  0 "gen9-luna high"       # clamped down to what it lists
expect real  terra    medium 0 "gen8.5-terra medium"  # only the older generation has it
expect real  astra    high   0 "gen9-astra high"
expect real  reserve  low    3 ""                     # hidden models are never picked
expect real  nova     low    3 ""                     # no such model: degrade
expect real  inherit  high   0 " high"
expect newer sol      low    0 "gen10-sol low"        # plain slug over -mini and a snapshot
expect variant sol    low    0 "gen10-sol-mini low"   # a variant still beats an older generation
expect efforts sol    low    0 "gen9-sol high"        # nothing at or below: clamp up
expect efforts luna   low    3 ""                     # only max/ultra listed
expect efforts terra  high   0 "gen9-terra medium"    # "extra-high" is not "high"
expect efforts mars   xhigh  0 "gen9-mars xhigh"      # no levels listed: pass through
expect efforts vega   high   0 "gen9-vega medium"     # levels as plain strings
expect efforts orion  medium 0 "gen9-orion high"      # never clamped down to low
expect efforts orion  low    0 "gen9-orion low"       # low when asked for
expect real  sol      ultra  2 ""
expect real  sol      max    2 ""
expect real  Sol      low    2 ""
expect real  gen9-sol low    2 ""                     # an alias, never a slug
expect nolisted sol   low    3 ""
expect arr   sol      low    3 ""
expect broken sol     low    3 ""
expect missing sol    low    3 ""

# expensive <alias-or-slug> <want-exit> — needs no catalogue, so none is given
expensive() {
  local rc; CODEX_MODELS_CACHE=/nonexistent "$here/codex-model.sh" --is-expensive "$1" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then echo "ok   is-expensive $1"
  else echo "FAIL is-expensive $1: exit $rc want $2"; fail=1; fi
}
expensive astra 0
expensive gen9-astra 0
expensive gen9-astra-pro-2031-06-30 0
expensive sol 1
expensive gen8.5-sol 1
expensive gen8.5-sol-mini 1                             # a variant of a standard name
expensive terra 1
expensive luna 1
expensive gen8 0                                        # no codename: not known to be standard
expensive nova 0                                        # a codename Codex ships later is opt-in

# pane.sh gate: argument errors and the opt-in gate exit 2 before Herdr is
# consulted; anything that passes them, without Herdr, exits 8 (NOHERDR).
echo brief > "$tmp/brief.md"
printf 'model = "gen8.5-sol"\n' > "$tmp/config-ok.toml"
printf 'model = "gen9-astra"\nmodel_reasoning_effort = "low"\n[tui]\nmodel = "x"\n' > "$tmp/config-astra.toml"
printf 'model = "gen9-astra-2031-06-30"\n' > "$tmp/config-snap.toml"
printf '[profiles.x]\nmodel = "gen9-astra"\n' > "$tmp/config-table.toml"
printf "model = 'gen9-astra'\n" > "$tmp/config-single.toml"
printf 'model = "gen8.5-sol"\nprofile = "big"\n[profiles.big]\nmodel = "gen9-astra"\n' > "$tmp/config-profile.toml"
printf 'model_reasoning_effort = "low"\n' > "$tmp/config-nomodel.toml"
gate() { env -u HERDR_ENV -u HERDR_PANE_ID -u DELEGATE_EXPENSIVE ${OPTIN:+DELEGATE_EXPENSIVE=1} \
  CODEX_MODELS_CACHE="${CACHE:-$tmp/real.json}" CODEX_CONFIG="${CONFIG:-$tmp/config-ok.toml}" \
  "$here/pane.sh" "$@" >/dev/null 2>&1; echo $?; }
check() { if [ "$1" = "$2" ]; then echo "ok   gate $3"; else echo "FAIL gate $3: exit $1 want $2"; fail=1; fi; }
b=$tmp/brief.md
check "$(gate codex medium impl slug "$b")"            2 "missing alias"
check "$(gate codex sol ultra impl slug "$b")"               2 "ultra refused"
check "$(OPTIN=1 gate codex astra ultra impl slug "$b")"     2 "ultra refused even with opt-in"
check "$(gate codex sol high impl slug)"                     2 "missing brief"
check "$(gate codex sol high impl slug /nonexistent)"        2 "unreadable brief"
check "$(gate codex sol high impl slug "$b" extra)"          2 "extra argument"
task() { printf 't%.0s' $(seq "$1"); }   # a task word of n characters
check "$(gate codex sol high impl "$(task 24)" "$b")"   2 "name over Herdr's 32 characters"
check "$(gate codex sol high impl "$(task 23)" "$b")"   8 "a name of exactly 32 characters"
check "$(gate claude sonnet high impl "$(task 21)" "$b")" 2 "claude name over Herdr's 32 characters"
check "$(gate codex sol high bogus slug "$b")"          2 "unknown role"
check "$(gate codex sol high review "$b")"              2 "role without a task"
for t in dlg-x impl-x review codex-x claude sol-x -x x- x--y x-y-z; do
  check "$(gate codex sol high review "$t" "$b")"       2 "task '$t' repeats the name or is malformed"
done
check "$(gate codex sol high review solar "$b")"        8 "a task that merely starts like the alias"
check "$(gate claude sonnet medium impl slug "$b")"    8 "valid claude, no herdr"
check "$(gate claude haiku high impl slug "$b")"       8 "claude haiku, no herdr"
check "$(gate claude gpt-4 high impl slug "$b")"       2 "malformed claude alias"
check "$(gate claude fable high impl slug "$b")"       2 "fable refused without opt-in"
check "$(OPTIN=1 gate claude fable high impl slug "$b")" 8 "fable allowed with opt-in"
check "$(gate claude nova high impl slug "$b")"        2 "a Claude alias that ships later is opt-in"
check "$(OPTIN=1 gate claude nova high impl slug "$b")" 8 "a later Claude alias with opt-in"
check "$(gate claude sonnet impl slug "$b")"           2 "claude needs an effort"
check "$(gate claude sonnet max impl slug "$b")"       2 "max refused"
check "$(gate claude sonnet ultra impl slug "$b")"     2 "ultra refused for claude too"
check "$(gate bogus sol high impl slug "$b")"          2 "unknown kind"
check "$(gate)"                                   2 "no arguments"
check "$(env HERDR_ENV=1 HERDR_PANE_ID= CODEX_MODELS_CACHE="$tmp/real.json" CODEX_CONFIG="$tmp/config-ok.toml" \
  "$here/pane.sh" claude sonnet medium impl slug "$b" >/dev/null 2>&1; echo $?)" 7 "inside Herdr but unusable: NOSTART, not NOHERDR"
check "$(gate codex sol high impl Bad_Slug "$b")"       2 "task with invalid characters"
check "$(gate codex sol high impl slug "$b")"                8 "valid, no herdr"
check "$(gate codex terra medium impl slug "$b")"            8 "older-generation alias"
check "$(gate codex astra high impl slug "$b")"              2 "astra refused without opt-in"
check "$(OPTIN=1 gate codex astra high impl slug "$b")"      8 "astra allowed with opt-in"
check "$(CACHE=$tmp/solfirst.json gate codex sol medium impl slug "$b")" 8 "sol ranked first in a new generation still launches"
check "$(gate codex --is-expensive astra impl slug "$b")"    2 "subcommand is not an alias"
check "$(CONFIG=$tmp/config-astra.toml gate codex inherit low impl slug "$b")" 2 "inherit onto astra refused"
check "$(CONFIG=$tmp/config-snap.toml gate codex inherit low impl slug "$b")" 2 "inherit onto an astra snapshot refused"
check "$(CONFIG=$tmp/config-astra.toml gate codex nova low impl slug "$b")" 2 "degrade onto astra refused"
check "$(CONFIG=$tmp/config-astra.toml OPTIN=1 gate codex inherit low impl slug "$b")" 8 "inherit onto astra with opt-in"
check "$(CONFIG=$tmp/config-table.toml gate codex inherit low impl slug "$b")" 2 "no top-level model: refused"
check "$(CONFIG=$tmp/config-nomodel.toml gate codex inherit low impl slug "$b")" 2 "no model key: refused"
check "$(CONFIG=$tmp/config-nomodel.toml OPTIN=1 gate codex inherit low impl slug "$b")" 8 "no model key with opt-in"
check "$(CONFIG=$tmp/config-single.toml gate codex inherit low impl slug "$b")" 2 "single-quoted astra refused"
check "$(CONFIG=$tmp/config-profile.toml gate codex inherit low impl slug "$b")" 2 "profile-selected astra refused"
check "$(CONFIG=$tmp/config-astra.toml CACHE=/nonexistent gate codex sol low impl slug "$b")" 2 "missing catalogue cannot fail open onto astra"
check "$(CONFIG=$tmp/config-astra.toml CACHE=$tmp/broken.json gate codex nova low impl slug "$b")" 2 "corrupt catalogue cannot fail open onto astra"
# A classifier that errors (here: jq failing on its codename query) must not
# read as "standard".
mkdir -p "$tmp/badjq"
printf '#!/bin/sh\ncase " $* " in *" -rn "*) exit 5 ;; esac\nexec %s "$@"\n' "$(command -v jq)" > "$tmp/badjq/jq"
chmod +x "$tmp/badjq/jq"
check "$(PATH="$tmp/badjq:$PATH" CONFIG=$tmp/config-astra.toml gate codex inherit low impl slug "$b")" 2 "classifier error cannot fail open onto astra"
check "$(PATH="$tmp/badjq:$PATH" gate codex sol low impl slug "$b")" 2 "classifier error refuses even a standard alias"
check "$(gate codex nova low impl slug "$b")"                2 "a codename that ships later is opt-in"
check "$(OPTIN=1 gate codex nova low impl slug "$b")"        8 "unknown alias with opt-in degrades onto the config model"
check "$(CACHE=/nonexistent gate codex sol low impl slug "$b")" 8 "missing catalogue degrades"

# pane.sh verdicts against a stub herdr. SCEN picks how the fake agent
# behaves; the third `agent get` while working is when it "finishes".
mkdir -p "$tmp/bin"
cat > "$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
S=$STATE
report='{"status":"complete","summary":"s","files_changed":[],"commands_run":[],"tests_run":[],"blockers":[],"concerns":[]}'
case "$1 $2" in
  "agent list") if [ -s "$S/agents" ]; then cat "$S/agents"; ! [ -e "$S/agentsjunk" ] || echo '{not json'; ! [ -e "$S/agentsexit" ] || exit 1
                elif [ "$SCEN" = race ]; then   # agents started so far, one "pane<TAB>name" line each
                  cat "$S/started" 2>/dev/null | jq -Rn '{result:{agents:[inputs | split("\t") | {tab_id:"t0", pane_id:.[0], name:.[1]}]}}'
                elif [ "$SCEN" = column ]; then
                  echo '{"result":{"agents":[{"tab_id":"t0","pane_id":"p9","name":"review-sol-x"},{"tab_id":"t9","pane_id":"p7","name":"impl-sol-y"},{"tab_id":"t0","pane_id":"p8","name":"reviewer"}]}}'
                else echo '{"result":{"agents":[]}}'; fi ;;
  "pane split") if [ "$SCEN" = race ]; then
                  id=p$RANDOM$RANDOM; echo "split $4 $6 $id" >> "$S/placements"; echo "{\"result\":{\"pane_id\":\"$id\"}}"; exit 0
                fi
                printf '%s\n' "$@" > "$S/split"
                [ "$SCEN" = splitfail ] && echo '{}' || echo '{"result":{"pane_id":"p1"}}' ;;
  "pane close") touch "$S/closed" ;;
  # placement fixtures: agents, tabs, panes and layout files in the state dir
  "tab list") [ -e "$S/tabfail" ] && exit 1; cat "$S/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "pane list") cat "$S/panes" 2>/dev/null || echo '{"result":{"panes":[]}}' ;;
  "pane layout") echo "$4" >> "$S/layoutq"; cat "$S/layout" 2>/dev/null || exit 1
                ! [ -e "$S/layoutjunk" ] || echo '{not json'; ! [ -e "$S/layoutexit" ] || exit 1 ;;
  "tab create") printf '%s\n' "$@" > "$S/tabcreate"; [ "$SCEN" != race ] || echo "tab $4" >> "$S/placements"
                echo '{"result":{"tab":{"tab_id":"wD:t7","label":"crew"},"root_pane":{"pane_id":"p2"}}}' ;;
  "agent start") printf '%s\n' "$@" > "$S/start"
                [ "$SCEN" != race ] || { sleep 0.3; printf '%s\t%s\n' "$7" "$3" >> "$S/started"; }
                # a long-lived child, as a started agent might leave behind
                [ "$SCEN" != lockchild ] || { sleep 5 >/dev/null 2>&1 & }
                [ "$SCEN" = gate ] && echo "Do you trust this folder?" > "$S/screen"
                case "$SCEN" in
                  trustblock) echo "Trust this folder? Codex can read, edit, and run files here" > "$S/screen"; exit 1 ;;
                  startfail) echo "error: agent crashed" > "$S/screen"; exit 1 ;;
                esac; exit 0 ;;
  "agent read") cat "$S/screen" 2>/dev/null ;;
  "agent send-keys") echo "$4" >> "$S/keys"; : > "$S/screen" ;;
  "agent prompt")
    n=$(( $(cat "$S/prompts" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/prompts"; echo "$4" > "$S/msg"
    rep=${4##*write your report to }; echo "${rep%% as JSON*}" > "$S/report"
    case "$SCEN" in
      nostart|race) ;;
      hooks|hooksresume) [ "$n" = 1 ] && echo "Hooks — 1 hook needs review" > "$S/screen"; echo working > "$S/status" ;;
      earlyblock) echo blocked > "$S/status" ;;
      idlequota) echo idle > "$S/status"; echo "■ You've hit your usage limit. Try again later." > "$S/screen" ;;
      *) echo working > "$S/status" ;;
    esac ;;
  "agent get")
    g=$(( $(cat "$S/gets" 2>/dev/null || echo 0) + 1 )); echo "$g" > "$S/gets"
    st=$(cat "$S/status" 2>/dev/null || echo idle)
    # --wait fixture: blocked for two polls, then working
    if { [ "$SCEN" = wait ] || [ "$SCEN" = keepwait ] || [ "$SCEN" = waitclose ]; } && [ "$st" = blocked ] && [ "$g" -ge 2 ]; then st=working g=0; echo 0 > "$S/gets"; echo working > "$S/status"; fi
    if [ "$st" = working ] && [ "$g" -ge 3 ]; then
      case "$SCEN" in
        happy|wait|waitclose|claude|keep|keepwait|resume|inherit|degrade|column|layout*|lock*) echo "$report" > "$(cat "$S/report")"; st=idle ;;
        # only a recovered prompt (escape, then exactly one resend) produces the report
        hooks|hooksresume) [ ! -s "$S/screen" ] && [ "$(cat "$S/prompts")" = 2 ] && { echo "$report" > "$(cat "$S/report")"; st=idle; } ;;
        quota|keepquota) st=idle; printf 'working\nYou have hit your usage limit. Try again later.\n' > "$S/screen" ;;
        mentions) st=blocked
          { echo "fixing the quota check, upgrade to the new usage limit text"; seq 20; echo "Allow command? y/n"; } > "$S/screen" ;;
        tailmention) st=blocked; printf 'Run: grep "usage limit reached" pane.sh\nAllow command? y/n\n' > "$S/screen" ;;
        noreport) st=idle ;;
        # a report whose concerns field is a string instead of an array
        badreport) echo "${report/\"concerns\":[]/\"concerns\":\"x\"}" > "$(cat "$S/report")"; st=idle ;;
        extrakey) echo "${report%\}},\"extra\":1}" > "$(cat "$S/report")"; st=idle ;;
        twoobjects) printf '%s\n%s\n' "$report" "$report" > "$(cat "$S/report")"; st=idle ;;
        # a report caught mid-write is not complete JSON yet: wait, never REPORT
        truncreport) echo '{"status":' > "$(cat "$S/report")"; st=idle ;;
        gone) exit 1 ;;
      esac
      echo "$st" > "$S/status"
    fi
    echo "{\"result\":{\"agent\":{\"agent_status\":\"$st\"}}}" ;;
esac
STUB
chmod +x "$tmp/bin/herdr"

# verdict <scenario> <want-exit> <want-first-word> <want-pane-closed:yes|no> [pane.sh args...]
verdict() {
  local sc=$1 want=$2 word=$3 close=$4; shift 4
  local st="$tmp/state-$sc" out rc closed=no
  mkdir -p "$st"
  [ $# -gt 0 ] || set -- codex sol medium impl "t-$sc" "$b"
  [ "$sc" = wait ] && { echo blocked > "$st/status"; echo "$tmp/handoff/w.json" > "$st/report"; }
  [ "$sc" = keepwait ] && { echo blocked > "$st/status"; echo "$tmp/handoff/kw.json" > "$st/report"; }
  [ "$sc" = waitclose ] && { echo blocked > "$st/status"; echo "$tmp/handoff/wc.json" > "$st/report"; }
  out=$(env SCEN="$sc" STATE="$st" PATH="$tmp/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p0 HERDR_TAB_ID=t0 HERDR_WORKSPACE_ID=wD \
    DELEGATE_HANDOFF_DIR="$tmp/handoff" CODEX_MODELS_CACHE="${CACHE:-$tmp/real.json}" CODEX_CONFIG="$tmp/config-ok.toml" \
    DELEGATE_POLL=0.1 DELEGATE_QUIET=2 DELEGATE_LAND=3 DELEGATE_KEEP="${KEEP:-}" \
    "$here/pane.sh" "$@" 2>/dev/null); rc=$?
  [ -e "$st/closed" ] && closed=yes
  if [ "$rc" = "$want" ] && [ "${out%% *}" = "$word" ] && [ "$closed" = "$close" ]; then echo "ok   pane $sc -> $word"
  else echo "FAIL pane $sc: exit $rc want $want, verdict '${out%% *}' want $word, closed $closed want $close"; fail=1; fi
}
mkdir -p "$tmp/handoff"
verdict happy       0 REPORT   yes
verdict claude      0 REPORT   yes claude sonnet high impl t-claude "$b"
leaf='You are a leaf worker. Do not delegate, spawn subagents, or start other agents. Do the work yourself.'
if grep -qx -- claude "$tmp/state-claude/start" && grep -A1 -x -- --model "$tmp/state-claude/start" | grep -qx sonnet \
   && grep -A1 -x -- --effort "$tmp/state-claude/start" | grep -qx high \
   && grep -A1 -x -- --append-system-prompt "$tmp/state-claude/start" | tail -1 | grep -qxF -- "$leaf"
then echo "ok   pane claude: launched as a sonnet leaf worker"; else echo "FAIL pane claude: launch args $(cat "$tmp/state-claude/start")"; fail=1; fi
if grep -qx -- codex "$tmp/state-happy/start" && grep -A1 -x -- -m "$tmp/state-happy/start" | grep -qx gen9-sol
then echo "ok   pane codex: launched with the resolved model"; else echo "FAIL pane codex: launch args $(cat "$tmp/state-happy/start")"; fail=1; fi
# The pane opens in the caller's directory (an SDD worktree).
if grep -A1 -x -- --cwd "$tmp/state-happy/split" | tail -1 | grep -qxF -- "$PWD"
then echo "ok   pane split: opens in the caller's directory"; else echo "FAIL pane split: args $(cat "$tmp/state-happy/split")"; fail=1; fi
# Claude workers start with Superpowers and the advisor disabled and HARNESS_LEAF set.
# Codex launch arguments omit Superpowers settings.
if grep -A1 -x -- --settings "$tmp/state-claude/start" | tail -1 \
     | jq -e '.enabledPlugins["superpowers@anthropic-plugin-directory"] == false
              and .env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL == "1"
              and .env.HARNESS_LEAF == "1"' >/dev/null 2>&1
then echo "ok   claude worker launch: advisor disabled and leaf marked"; else echo "FAIL claude worker launch: missing worker settings"; fail=1; fi
if ! grep -q superpowers "$tmp/state-happy/start"
then echo "ok   pane codex: launch arguments omit Superpowers settings"; else echo "FAIL pane codex: unexpected Superpowers launch setting"; fail=1; fi
missing=
for k in status summary files_changed commands_run tests_run blockers concerns; do
  grep -q "\b$k\b" "$tmp/state-claude/msg" || missing="$missing $k"
done
if [ -z "$missing" ] && grep -q "write your report to $tmp/handoff/impl-t-claude-" "$tmp/state-claude/msg"
then echo "ok   pane prompt: names the report path and every key"; else echo "FAIL pane prompt: missing$missing"; fail=1; fi
if grep -q "summary (a string), and files_changed, commands_run, tests_run, blockers, concerns (each an array of strings)" "$tmp/state-claude/msg"
then echo "ok   pane prompt: says the list keys are arrays of strings"; else echo "FAIL pane prompt: list key types not stated"; fail=1; fi
# The pane is named <role>-<model>-<task>: the alias, or "codex" when
# config.toml's model runs (inherit, or an alias that degraded onto it).
verdict inherit     0 REPORT   yes codex inherit medium review t-inherit "$b"
# The worker pane carries its role so the herdr sidebar can label it.
if grep -A1 -x -- --env "$tmp/state-inherit/split" | tail -1 | grep -qxF -- HARNESS_ROLE=review
then echo "ok   pane split: role in the worker's environment"; else echo "FAIL pane split: role env $(cat "$tmp/state-inherit/split")"; fail=1; fi
CACHE=/nonexistent verdict degrade 0 REPORT yes codex sol medium review t-degrade "$b"
for want in claude:impl-sonnet-t-claude happy:impl-sol-t-happy inherit:review-codex-t-inherit degrade:review-codex-t-degrade; do
  got=$(sed -n 3p "$tmp/state-${want%%:*}/start" 2>/dev/null)
  if [ "$got" = "${want#*:}" ]; then echo "ok   pane name: $got"; else echo "FAIL pane name: '$got' want ${want#*:}"; fail=1; fi
done
# A later delegate joins this tab's delegate column, found by its role prefix.
verdict column      0 REPORT   yes
if [ "$(tr '\n' ' ' < "$tmp/state-column/split")" = "pane split --pane p9 --direction down --cwd $PWD --ratio 0.5 --no-focus --env HARNESS_ROLE=impl " ]
then echo "ok   pane column: splits the last delegate in this tab"; else echo "FAIL pane column: split $(cat "$tmp/state-column/split")"; fail=1; fi
# Placement: two workers beside the orchestrator, then 2x2 crew tabs. Each case
# writes its Herdr fixtures into the scenario's state dir, runs a launch, and
# checks the recorded `pane split` or `tab create` arguments.
fx_dir() { mkdir -p "$tmp/state-layout-$1"; echo "$tmp/state-layout-$1"; }
fx_agents() { local d=$1; shift   # column workers, by pane
  jq -n '{result:{agents:[$ARGS.positional[] | {tab_id:"t0", pane_id:., name:("review-sol-" + .)}]}}' --args "$@" > "$d/agents"; }
fx_tabs() { local d=$1; shift     # "<tab_id>=<label>"
  jq -n '{result:{tabs:[$ARGS.positional[] | split("=") | {tab_id:.[0], label:.[1]}]}}' --args "$@" > "$d/tabs"; }
fx_panes() { local d=$1; shift    # "<tab_id>=<pane>"
  jq -n '{result:{panes:[$ARGS.positional[] | split("=") | {pane_id:.[1], tab_id:.[0]}]}}' --args "$@" > "$d/panes"; }
fx_layout() { local d=$1; shift   # "<pane>:<width>:<height>"
  jq -n '{result:{layout:{tab_id:"x", splits:[], panes:[$ARGS.positional[] | split(":")
    | {pane_id:.[0], rect:{x:0, y:0, width:(.[1] | tonumber), height:(.[2] | tonumber)}}]}}}' --args "$@" > "$d/layout"; }
# launch <case> [role]: one worker launched against the case's fixtures
launch() { verdict "layout-$1" 0 REPORT yes codex sol medium "${2:-impl}" "lay-$1" "$b"; }
# recorded <label> <state-dir> <file> <want args, space-joined>
recorded() {
  local got; got=$(tr '\n' ' ' < "$2/$3" 2>/dev/null)
  if [ "$got" = "$4" ]; then echo "ok   layout: $1"; else echo "FAIL layout: $1: $3 '$got' want '$4'"; fail=1; fi
}
common="--cwd $PWD --ratio 0.5 --no-focus --env HARNESS_ROLE=impl "

d=$(fx_dir first); launch first
recorded "first worker splits the orchestrator right" "$d" split "pane split --pane p0 --direction right $common"

d=$(fx_dir second); fx_agents "$d" p9; fx_layout "$d" p0:110:66 p9:109:66; launch second
recorded "second worker splits the column pane down" "$d" split "pane split --pane p9 --direction down $common"

d=$(fx_dir third); fx_agents "$d" p9 p8; fx_layout "$d" p0:110:66 p9:109:33 p8:109:33; launch third
recorded "third worker opens the crew tab" "$d" tabcreate "tab create --label crew --cwd $PWD --no-focus --env HARNESS_ROLE=impl "
if [ ! -e "$d/split" ] && grep -A1 -x -- --pane "$d/start" | tail -1 | grep -qx p2
then echo "ok   layout: worker starts in the crew tab's root pane"; else echo "FAIL layout: crew root pane: start '$(cat "$d/start" 2>/dev/null)'"; fail=1; fi

d=$(fx_dir crewone); fx_agents "$d" p9 p8; fx_tabs "$d" wD:t2=crew; fx_panes "$d" wD:t2=pc1
fx_layout "$d" pc1:219:66; launch crewone
recorded "crew with one pane splits right" "$d" split "pane split --pane pc1 --direction right $common"

d=$(fx_dir crewgap); fx_agents "$d" p9 p8; fx_tabs "$d" wD:t2=crew; fx_panes "$d" wD:t2=pb wD:t2=pc wD:t2=pa
fx_layout "$d" pb:109:33 pc:109:33 pa:109:66; launch crewgap
recorded "crew gap refilled down" "$d" split "pane split --pane pa --direction down $common"

d=$(fx_dir crewfull); fx_agents "$d" p9 p8; fx_tabs "$d" wD:t2=crew; fx_panes "$d" wD:t2=pa wD:t2=pb wD:t2=pc wD:t2=pd
fx_layout "$d" pa:109:33 pb:109:33 pc:109:33 pd:109:33; launch crewfull
recorded "full crew opens crew-2" "$d" tabcreate "tab create --label crew-2 --cwd $PWD --no-focus --env HARNESS_ROLE=impl "

d=$(fx_dir crew2); fx_agents "$d" p9 p8; fx_tabs "$d" wD:t2=crew wD:t3=crew-2
fx_panes "$d" wD:t2=pa wD:t2=pb wD:t2=pc wD:t2=pd wD:t3=pq1 wD:t3=pq2; fx_layout "$d" pq1:109:66 pq2:109:66; launch crew2
recorded "crew-2 with room is used" "$d" split "pane split --pane pq1 --direction down $common"

d=$(fx_dir otherws); fx_agents "$d" p9 p8; fx_tabs "$d" wE:t2=crew; fx_panes "$d" wE:t2=px; fx_layout "$d" px:219:66; launch otherws
recorded "other workspace's crew ignored" "$d" tabcreate "tab create --label crew --cwd $PWD --no-focus --env HARNESS_ROLE=impl "

d=$(fx_dir tabfail); fx_agents "$d" p9 p8; touch "$d/tabfail"; launch tabfail
recorded "tab list failure falls back to the column" "$d" split "pane split --pane p8 --direction down $common"

# a read that prints something usable and then fails is not trusted
d=$(fx_dir layjunk); fx_agents "$d" p9 p8; fx_tabs "$d" wD:t2=crew; fx_panes "$d" wD:t2=pc1; fx_layout "$d" pc1:219:66
touch "$d/layoutjunk"; launch layjunk
recorded "layout followed by malformed data falls back to the column" "$d" split "pane split --pane p8 --direction down $common"
d=$(fx_dir layexit); fx_agents "$d" p9 p8; fx_tabs "$d" wD:t2=crew; fx_panes "$d" wD:t2=pc1; fx_layout "$d" pc1:219:66
touch "$d/layoutexit"; launch layexit
recorded "layout from a failing herdr falls back to the column" "$d" split "pane split --pane p8 --direction down $common"
d=$(fx_dir agjunk); fx_agents "$d" p9 p8; touch "$d/agentsjunk"; launch agjunk
recorded "agent list followed by malformed data counts no column" "$d" split "pane split --pane p0 --direction right $common"
d=$(fx_dir agexit); fx_agents "$d" p9 p8; touch "$d/agentsexit"; launch agexit
recorded "agent list from a failing herdr counts no column" "$d" split "pane split --pane p0 --direction right $common"

# the role reaches every split and every tab create
d=$(fx_dir rolesplit); launch rolesplit review
recorded "role on every split" "$d" split "pane split --pane p0 --direction right --cwd $PWD --ratio 0.5 --no-focus --env HARNESS_ROLE=review "
d=$(fx_dir roletab); fx_agents "$d" p9 p8; launch roletab fix
recorded "role on every tab" "$d" tabcreate "tab create --label crew --cwd $PWD --no-focus --env HARNESS_ROLE=fix "
# The placement lock: launches started together are placed one after another.
# "race" has the stub list the agents started so far and take a moment to
# start one, so a launch that counts the column before the previous one has
# started sees it empty.
st=$tmp/state-race; mkdir -p "$st" "$tmp/handoff-race"
for t in lk1 lk2 lk3; do
  env SCEN=race STATE="$st" PATH="$tmp/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p0 HERDR_TAB_ID=t0 HERDR_WORKSPACE_ID=wD \
    DELEGATE_HANDOFF_DIR="$tmp/handoff-race" CODEX_MODELS_CACHE="$tmp/real.json" CODEX_CONFIG="$tmp/config-ok.toml" \
    DELEGATE_POLL=0.1 DELEGATE_LAND=0 "$here/pane.sh" codex sol medium impl "$t" "$b" >/dev/null 2>&1 &
done
wait
rid=$(awk '$2 == "p0" && $3 == "right" { print $4 }' "$st/placements" 2>/dev/null)
if [ "$(wc -l < "$st/placements" 2>/dev/null)" -eq 3 ] && [ "$(grep -c '^split p0 ' "$st/placements")" -eq 1 ] \
   && [ -n "$rid" ] && [ "$(grep -c "^split $rid down " "$st/placements")" -eq 1 ] \
   && [ "$(grep -c '^tab crew$' "$st/placements")" -eq 1 ]
then echo "ok   lock: simultaneous launches stack in order"
else echo "FAIL lock: simultaneous launches placed as: $(paste -sd'|' "$st/placements" 2>/dev/null)"; fail=1; fi
if flock -n "$tmp/handoff-race/.place.lock" true
then echo "ok   lock: three simultaneous launches leave no lock held"; else echo "FAIL lock: held after simultaneous launches"; fail=1; fi

lockfile=$tmp/handoff/.place.lock
mkdir -p "$tmp/handoff"
# lockrun <scenario>: one launch against the shared handoff dir; prints its output.
lockrun() {
  mkdir -p "$tmp/state-$1"
  env SCEN="$1" STATE="$tmp/state-$1" PATH="${LPATH:-$tmp/bin:$PATH}" HERDR_ENV=1 HERDR_PANE_ID=p0 HERDR_TAB_ID=t0 HERDR_WORKSPACE_ID=wD \
    DELEGATE_HANDOFF_DIR="$tmp/handoff" CODEX_MODELS_CACHE="$tmp/real.json" CODEX_CONFIG="$tmp/config-ok.toml" \
    DELEGATE_POLL=0.1 DELEGATE_QUIET=2 DELEGATE_LAND=3 "$here/pane.sh" codex sol medium impl "t-$1" "$b" 2>/dev/null
}
# lockhold: a background process holding the lock until killed; sets $holder.
lockhold() {
  rm -f "$tmp/held"
  ( exec 8>>"$lockfile"; flock 8 && : > "$tmp/held"; exec sleep 30 ) & holder=$!
  until [ -e "$tmp/held" ]; do sleep 0.05; done
}
# lockfree: whether the lock can be taken at once
lockfree() { flock -n "$lockfile" true; }

# A holder killed without releasing: the kernel frees the lock at once.
lockhold; kill "$holder"; wait "$holder" 2>/dev/null
t0=$SECONDS; out=$(DELEGATE_LOCK_WAIT=30 lockrun lockkilled)
if [ "${out%% *}" = REPORT ] && [ $(( SECONDS - t0 )) -lt 10 ] && ! grep -q 'placement lock' <<<"$out"
then echo "ok   lock: a lock held by a killed process is free at once"; else echo "FAIL lock: killed holder delayed the launch (${out%% *}, $(( SECONDS - t0 ))s)"; fail=1; fi

# A live holder that never lets go: the launch waits DELEGATE_LOCK_WAIT, then
# goes ahead without the lock and says so.
lockhold
t0=$SECONDS; out=$(DELEGATE_LOCK_WAIT=1 lockrun locknote)
if [ "${out%% *}" = REPORT ] && [ $(( SECONDS - t0 )) -ge 1 ] && [ $(( SECONDS - t0 )) -lt 10 ] \
   && grep -q '^placement lock not free after 1s; launched without it$' <<<"$out" && ! lockfree
then echo "ok   lock: a lock that never frees times out and the launch proceeds"
else echo "FAIL lock: timeout (${out%% *}, waited $(( SECONDS - t0 ))s, output: $(tail -n +2 <<<"$out" | head -n 2 | paste -sd'|' -))"; fail=1; fi
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null

# Without flock on PATH the launch proceeds, silently.
farm=$tmp/noflock; mkdir -p "$farm"
for f in /usr/bin/* /bin/*; do [ -L "$farm/${f##*/}" ] || [ "${f##*/}" = flock ] || ln -s "$f" "$farm/${f##*/}"; done
out=$(LPATH="$tmp/bin:$farm" lockrun locknoflock)
if [ "${out%% *}" = REPORT ] && ! grep -q 'placement lock' <<<"$out" && ! [ -e "$farm/flock" ]
then echo "ok   lock: no flock on PATH: the launch proceeds"; else echo "FAIL lock: launch without flock gave '${out%% *}'"; fail=1; fi

# Released on every path: the next launch could take the lock at once.
verdict lockfree 0 REPORT yes
lockfree && echo "ok   lock: released after launch" || { echo "FAIL lock: still held after a launch"; fail=1; }
verdict nostart 7 NOSTART no
lockfree && echo "ok   lock: released after a NOSTART launch" || { echo "FAIL lock: still held after NOSTART"; fail=1; }
verdict startfail 7 NOSTART yes
lockfree && echo "ok   lock: released after a failed start" || { echo "FAIL lock: still held after a failed start"; fail=1; }
# A child the started agent leaves behind must not keep the lock.
out=$(lockrun lockchild)
lockfree && echo "ok   lock: a long-lived child of agent start does not keep the lock" || { echo "FAIL lock: held by a child of agent start (${out%% *})"; fail=1; }
verdict hooks       0 REPORT   yes    # hook-review Escape and resend
if [ "$(cat "$tmp/state-hooks/keys" 2>/dev/null)" = esc ] && [ "$(cat "$tmp/state-hooks/prompts")" = 2 ]
then echo "ok   pane hooks: one escape, one resend"; else echo "FAIL pane hooks: escape/resend not as expected"; fail=1; fi
verdict quota       5 QUOTA    yes
verdict idlequota   5 QUOTA    yes    # rejected before it ever started
verdict mentions    3 BLOCKED  no     # a task that talks about limits is not a quota hit
verdict tailmention 3 BLOCKED  no     # not even with the words at the bottom of the screen
verdict earlyblock  3 BLOCKED  no     # an approval question before the first poll
verdict noreport    4 NOREPORT no
# A malformed report is no report: moved aside so a --wait after re-prompting
# waits for a fresh one, and the reason is printed.
for sc in badreport extrakey twoobjects; do
  verdict "$sc" 4 NOREPORT no
  bad=$(cat "$tmp/state-$sc/report")
  if [ ! -e "$bad" ] && [ -s "$bad.invalid" ]
  then echo "ok   pane $sc: moved to .invalid"; else echo "FAIL pane $sc: not moved aside"; fail=1; fi
done
verdict truncreport 4 NOREPORT no
bad=$(cat "$tmp/state-truncreport/report")
if [ -e "$bad" ] && [ ! -e "$bad.invalid" ]
then echo "ok   pane truncreport: left in place, not judged"; else echo "FAIL pane truncreport: judged a partial write"; fail=1; fi
verdict nostart     7 NOSTART  no
verdict gate        7 NOSTART  no
verdict splitfail   7 NOSTART  no
verdict trustblock  3 BLOCKED  no    # a first-run trust prompt stays answerable
verdict startfail   7 NOSTART  yes   # any other start failure still closes the pane
verdict gone        6 GONE     no
verdict wait        0 REPORT   no  --wait p1 "$tmp/handoff/w.json"   # --wait allows an initial blocked grace period and keeps the pane
KEEP=0 verdict waitclose 0 REPORT yes --wait p1 "$tmp/handoff/wc.json"   # DELEGATE_KEEP=0 still closes it
verdict timeout     124 TIMEOUT no --wait p1 "$tmp/handoff/none.json" 0
# --resume: a follow-up prompt into a kept pane, with a fresh report path; the
# pane stays open for the next round.
printf 'Fix the finding: tests/x.sh:3 asserts nothing.\n' > "$tmp/fix.md"
verdict resume    0 REPORT  no --resume p1 "$tmp/fix.md"
if grep -qF 'Fix the finding: tests/x.sh:3 asserts nothing.' "$tmp/state-resume/msg" \
   && grep -q "write your report to $tmp/handoff/resume-p1-[A-Za-z0-9]*.json as JSON with exactly these keys" "$tmp/state-resume/msg"
then echo "ok   pane resume: message plus a fresh report path"; else echo "FAIL pane resume: prompt was '$(cat "$tmp/state-resume/msg" 2>/dev/null)'"; fail=1; fi
verdict hooksresume 0 REPORT no --resume p1 "$tmp/fix.md" 1   # hook-review Escape and resend on resume
if [ "$(cat "$tmp/state-hooksresume/keys" 2>/dev/null)" = esc ] && [ "$(cat "$tmp/state-hooksresume/prompts")" = 2 ]
then echo "ok   pane resume hooks: one escape, one resend"; else echo "FAIL pane resume hooks: not recovered"; fail=1; fi
# Two resumes of one pane in the same second get different report paths.
uniq_report() { mkdir -p "$tmp/state-uniq"; env PATH="$tmp/bin:$PATH" STATE="$tmp/state-uniq" SCEN=nostart HERDR_ENV=1 \
  DELEGATE_HANDOFF_DIR="$tmp/handoff" DELEGATE_LAND=0 DELEGATE_POLL=0.1 \
  "$here/pane.sh" --resume p1 "$tmp/fix.md" 2>/dev/null | head -1 | grep -o 'report=[^ ]*'; }
r1=$(uniq_report); r2=$(uniq_report)
if [ -n "$r1" ] && [ "$r1" != "$r2" ]; then echo "ok   pane resume: a unique report path each time"
else echo "FAIL pane resume: report paths '$r1' and '$r2'"; fail=1; fi
check "$(gate --resume p1 /nonexistent)"           2 "resume needs a readable message"
check "$(gate --resume p1)"                        2 "resume needs a message file"
KEEP=1 verdict keep      0 REPORT  no     # kept open for a fix round
KEEP=1 verdict keepwait  0 REPORT  no --wait p1 "$tmp/handoff/kw.json"   # and again after the round
KEEP=1 verdict keepquota 5 QUOTA   yes    # a pane out of quota is closed regardless

exit $fail
