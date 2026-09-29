#!/usr/bin/env bash
# Spawn a delegate agent in a Herdr pane, placed per the pane-lifecycle rules in
# handoff.md, with the launch argv from its "Launching a worker" section.
#
#   herdr-spawn.sh codex  <alias> <effort> <slug>
#       alias: a Codex codename (sol, terra, luna, ...) | inherit
#       effort: low|medium|high|xhigh
#   herdr-spawn.sh claude <alias> <slug>     # alias: opus|sonnet|haiku|fable
#
# The Codex alias resolves to the newest listed model of that name through
# codex-model.sh at launch. One it cannot resolve degrades to inherit (no -m,
# ~/.codex/config.toml decides) and says why on stderr rather than failing the
# delegation. Claude fable, and any Codex launch that would run an opt-in-only
# model — by alias, or because config.toml names one — need
# DELEGATE_EXPENSIVE=1 (the user asked for them).
#
# Prints the new pane id on stdout; everything else goes to stderr.
# Exit: 0 ready, 2 usage, 3 no Herdr, 4 start failed, 5 start gate on screen
set -euo pipefail

usage() { echo "usage: $0 codex <codename|inherit> <effort> <slug> | claude <opus|sonnet|haiku|fable> <slug>" >&2; exit 2; }
kind=${1:-}
case "$kind" in
  codex)  [ $# -eq 4 ] || usage; tier=$2 effort=$3 slug=$4 ;;
  claude) [ $# -eq 3 ] || usage; tier=$2 slug=$3
          case "$tier" in opus|sonnet|haiku|fable) ;; *) usage ;; esac ;;
  *) usage ;;
esac
[ -n "$tier" ] && [ -n "$slug" ] || usage

# Claude fable costs far more of the user's quota. It runs only when the user
# explicitly asked for it in this conversation, and the caller says so by
# setting DELEGATE_EXPENSIVE=1 on this one command.
optin() { [ "${DELEGATE_EXPENSIVE:-}" = 1 ] || {
  echo "$1 runs only on the user's explicit request; use sol or opus instead, or set DELEGATE_EXPENSIVE=1 if the user asked" >&2
  exit 2; }; }
[ "$kind:$tier" != claude:fable ] || optin "claude fable"

# Resolve before touching Herdr, so a bad tier or effort never leaves a pane.
if [ "$kind" = codex ]; then
  here=$(dirname "$(readlink -f "$0")")
  rc=0; resolved=$("$here/codex-model.sh" "$tier" "$effort") || rc=$?
  case "$rc" in
    0) ;;
    2) exit 2 ;;
    3) echo "codex alias $tier unresolved (reason above); degrading to inherit" >&2
       resolved=$("$here/codex-model.sh" inherit "$effort") ;;
    *) echo "codex-model.sh failed (exit $rc)" >&2; exit 4 ;;
  esac
  model=$(sed -n 1p <<<"$resolved") effort=$(sed -n 2p <<<"$resolved")

  [ -n "$effort" ] || { echo "codex alias $tier resolved no effort" >&2; exit 2; }

  # Opt-in-only models are gated on the alias asked for and on the model that
  # will actually launch: inherit, and the degrade path, run whatever
  # config.toml selects (a profile's model overrides the top-level one). A
  # launch whose model cannot be determined is refused, never waved through.
  launched=$model
  if [ -z "$launched" ]; then
    launched=$(python3 -c '
import sys, tomllib
with open(sys.argv[1], "rb") as f: c = tomllib.load(f)
p = c.get("profile")
m = (c.get("profiles", {}).get(p, {}).get("model") if p else None) or c.get("model") or ""
print(m if isinstance(m, str) else "")' "${CODEX_CONFIG:-$HOME/.codex/config.toml}" 2>/dev/null || true)
    [ -n "$launched" ] || [ "${DELEGATE_EXPENSIVE:-}" = 1 ] || {
      echo "codex $tier would run config.toml's model, which cannot be determined; name an alias, or set DELEGATE_EXPENSIVE=1 if the user accepts any model" >&2
      exit 2; }
  fi
  for probe in "$tier" ${launched:+"$launched"}; do
    [ "$probe" != inherit ] || continue
    if "$here/codex-model.sh" --is-expensive "$probe" 2>/dev/null; then
      optin "codex $probe (opt-in only)"
    fi
  done
  args=(-c "model_reasoning_effort=$effort")
  [ -z "$model" ] || args=(-m "$model" "${args[@]}")
else
  args=(--model "$tier"
        --append-system-prompt 'You are a leaf worker. Do not delegate, spawn subagents, or start other agents. Do the work yourself.')
fi
[ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null && [ -n "${HERDR_PANE_ID:-}" ] || { echo "herdr unavailable" >&2; exit 3; }
[ "$kind" = claude ] || echo "codex: ${model:-${launched:-unknown} from config.toml} ($tier), effort $effort" >&2

name="dlg-${kind}-${slug}"
mkdir -p /tmp/codex-handoff

# Rule 1: the orchestrator pane gets at most one delegate child. Later delegates
# subdivide the delegate column instead of halving the orchestrator again.
column=$(herdr agent list | jq -r --arg tab "${HERDR_TAB_ID:-}" \
  '[.result.agents[] | select(.tab_id == $tab and ((.name // "") | startswith("dlg-")))] | last | .pane_id // empty')
if [ -n "$column" ]; then
  split=(--pane "$column" --direction down)
else
  split=(--pane "$HERDR_PANE_ID" --direction right)
fi
pane=$(herdr pane split "${split[@]}" --ratio 0.5 --no-focus --env CLAUDE_AGENT_DEPTH=1 \
  | jq -r '.result.pane_id // .result.pane.pane_id // empty')
[ -n "$pane" ] || { echo "pane split failed" >&2; exit 4; }

if ! herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 -- "${args[@]}" >/dev/null; then
  echo "agent start failed in $pane" >&2
  herdr pane read "$pane" --lines 30 >&2 2>/dev/null || true
  herdr pane close "$pane" >/dev/null 2>&1 || true
  exit 4
fi

# A first-run or trust gate can sit on screen while Herdr reports idle.
screen=$(herdr agent read "$pane" --source visible --format text 2>/dev/null || true)
if grep -qiE 'do you trust|trust this (folder|directory)|sign in|log ?in to|press enter to continue' <<<"$screen"; then
  echo "start gate on screen in $pane:" >&2
  tail -n 25 <<<"$screen" >&2
  echo "$pane"
  exit 5
fi
echo "$pane"
