#!/usr/bin/env bash
# Fixture tests for codex-model.sh and herdr-spawn.sh's argument handling and
# opt-in gate. Synthetic catalogues only; never touches Herdr or Codex.
#   bash ~/.claude/skills/_shared/test-codex-model.sh
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
  jq -n '{slug:"gen9-vega", visibility:"list", priority:5, supported_reasoning_levels:["low","medium"]}'; } | catalogue efforts
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
expensive gen8 1
expensive nova 1                                        # new codenames are added to EXPENSIVE by hand

# herdr-spawn.sh: argument errors and the opt-in gate exit 2 before Herdr is
# consulted; anything that passes them, without Herdr, exits 3.
printf 'model = "gen8.5-sol"\n' > "$tmp/config-ok.toml"
printf 'model = "gen9-astra"\nmodel_reasoning_effort = "low"\n[tui]\nmodel = "x"\n' > "$tmp/config-astra.toml"
printf 'model = "gen9-astra-2031-06-30"\n' > "$tmp/config-snap.toml"
printf '[profiles.x]\nmodel = "gen9-astra"\n' > "$tmp/config-table.toml"
printf "model = 'gen9-astra'\n" > "$tmp/config-single.toml"
printf 'model = "gen8.5-sol"\nprofile = "big"\n[profiles.big]\nmodel = "gen9-astra"\n' > "$tmp/config-profile.toml"
printf 'model_reasoning_effort = "low"\n' > "$tmp/config-nomodel.toml"
spawn() { env -u HERDR_ENV -u HERDR_PANE_ID -u DELEGATE_EXPENSIVE ${OPTIN:+DELEGATE_EXPENSIVE=1} \
  CODEX_MODELS_CACHE="${CACHE:-$tmp/real.json}" CODEX_CONFIG="${CONFIG:-$tmp/config-ok.toml}" \
  "$here/herdr-spawn.sh" "$@" >/dev/null 2>&1; echo $?; }
check() { if [ "$1" = "$2" ]; then echo "ok   spawn $3"; else echo "FAIL spawn $3: exit $1 want $2"; fail=1; fi; }
check "$(spawn codex medium slug)"                2 "old two-arg codex form"
check "$(spawn codex sol ultra slug)"             2 "ultra refused"
check "$(OPTIN=1 spawn codex astra ultra slug)"   2 "ultra refused even with opt-in"
check "$(spawn codex sol high)"                   2 "missing slug"
check "$(spawn codex sol high slug extra)"        2 "extra codex argument"
check "$(spawn claude opus slug extra)"           2 "extra claude argument"
check "$(spawn claude gpt-4 slug)"                2 "unknown claude alias"
check "$(spawn bogus x y)"                        2 "unknown kind"
check "$(spawn codex sol high slug)"              3 "valid codex, no herdr"
check "$(spawn codex terra medium slug)"          3 "older-generation alias"
check "$(spawn claude sonnet slug)"               3 "valid claude, no herdr"
check "$(spawn codex astra high slug)"            2 "astra refused without opt-in"
check "$(spawn claude fable slug)"                2 "fable refused without opt-in"
check "$(OPTIN=1 spawn codex astra high slug)"    3 "astra allowed with opt-in"
check "$(OPTIN=1 spawn claude fable slug)"        3 "fable allowed with opt-in"
check "$(CACHE=$tmp/solfirst.json spawn codex sol medium slug)" 3 "sol ranked first in a new generation still launches"
check "$(spawn codex --is-expensive astra slug)"  2 "subcommand is not an alias"
check "$(spawn codex is-expensive high slug)"     2 "hyphenated alias rejected"
check "$(CONFIG=$tmp/config-astra.toml spawn codex inherit low slug)" 2 "inherit onto astra refused"
check "$(CONFIG=$tmp/config-snap.toml spawn codex inherit low slug)" 2 "inherit onto an astra snapshot refused"
check "$(CONFIG=$tmp/config-astra.toml spawn codex nova low slug)" 2 "degrade onto astra refused"
check "$(CONFIG=$tmp/config-astra.toml OPTIN=1 spawn codex inherit low slug)" 3 "inherit onto astra with opt-in"
check "$(CONFIG=$tmp/config-table.toml spawn codex inherit low slug)" 2 "no top-level model: refused, not waved through"
check "$(CONFIG=$tmp/config-nomodel.toml spawn codex inherit low slug)" 2 "no model key: refused"
check "$(CONFIG=$tmp/config-nomodel.toml OPTIN=1 spawn codex inherit low slug)" 3 "no model key with opt-in"
check "$(CONFIG=$tmp/config-single.toml spawn codex inherit low slug)" 2 "single-quoted astra refused"
check "$(CONFIG=$tmp/config-profile.toml spawn codex inherit low slug)" 2 "profile-selected astra refused"
check "$(CONFIG=$tmp/config-astra.toml CACHE=/nonexistent spawn codex sol low slug)" 2 "missing catalogue cannot fail open onto astra"
check "$(CONFIG=$tmp/config-astra.toml CACHE=$tmp/broken.json spawn codex inherit low slug)" 2 "corrupt catalogue cannot fail open onto astra"
check "$(spawn codex nova low slug)"              3 "unknown alias degrades onto a cheap config model"
check "$(CACHE=/nonexistent spawn codex sol low slug)" 3 "missing catalogue degrades"

exit $fail
