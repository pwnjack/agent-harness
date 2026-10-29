#!/usr/bin/env bash
# Report repo, role, model and effort for this pane to the Herdr sidebar.
# Usage: sidebar-report.sh <cwd> <model> <effort>. Always silent, exit 0.
# HARNESS_SIDEBAR_SYNC=1 waits for the herdr call; by default it is detached.
set -euo pipefail

cwd=${1:-} model=${2:-} effort=${3:-}
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# A linked worktree names its main repository, a bare one drops `.git`,
# a submodule (common dir under .git/modules) names its own checkout.
repo=''
if common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  case $common in
    */.git) repo=${common%/.git}; repo=${repo##*/} ;;
    *.git) repo=${common##*/}; repo=${repo%.git} ;;
    *) top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && repo=${top##*/} ;;
  esac
fi
[ -n "$repo" ] || repo=$(basename -- "$cwd" 2>/dev/null) || repo=''

case ${HARNESS_ROLE:-} in
  impl) role=implementer ;;
  review) role=reviewer ;;
  explore) role=explorer ;;
  fix) role=fixer ;;
  *) role=orchestrator ;;
esac

case $effort in
  low) meter='▰▱▱▱▱' ;;
  medium) meter='▰▰▱▱▱' ;;
  high) meter='▰▰▰▱▱' ;;
  xhigh) meter='▰▰▰▰▱' ;;
  max) meter='▰▰▰▰▰' ;;
  *) meter='' ;;
esac

# Reports are patches, so every token is either set or cleared.
args=(--token "repo=$repo" --token "role=$role")
if [ -n "$model" ]; then args+=(--token "model=${model:0:80}"); else args+=(--clear-token model); fi
if [ -n "$meter" ]; then args+=(--token "effort=$meter $effort"); else args+=(--clear-token effort); fi

# One cache per Herdr socket and pane; an identical report is resent only
# once the cache is over a minute old, to recover from a server restart.
key=$(printf '%s|%s' "${HERDR_SOCKET_PATH:-}" "$HERDR_PANE_ID" | cksum) || exit 0
key=${key%% *}
cache="${XDG_STATE_HOME:-$HOME/.local/state}/harness/sidebar/$key"
new=$(printf '%s\n' "${args[@]}")
if [ -f "$cache" ] && [ "$(cat -- "$cache" 2>/dev/null)" = "$new" ] \
   && [ -z "$(find "$cache" -mmin +1 2>/dev/null)" ]; then
  exit 0
fi
mkdir -p -- "${cache%/*}" 2>/dev/null && printf '%s\n' "$new" 2>/dev/null > "$cache" || true

# Taken before detaching, so a delayed older report is ignored by Herdr.
seq=$(jq -n 'now*1000000|floor' 2>/dev/null) || exit 0

# A two-second watchdog keeps a hung socket from blocking or piling up.
send() {
  herdr pane report-metadata "$HERDR_PANE_ID" --source harness:sidebar --seq "$seq" "${args[@]}" \
    </dev/null >/dev/null 2>&1 &
  local call=$!
  (sleep 2; kill "$call") </dev/null >/dev/null 2>&1 &
  local watcher=$!
  wait "$call" 2>/dev/null || true
  kill "$watcher" 2>/dev/null || true
}
if [ "${HARNESS_SIDEBAR_SYNC:-}" = 1 ]; then
  send
else
  (send) </dev/null >/dev/null 2>&1 &
fi
exit 0
