#!/usr/bin/env bash
# Block until a delegate pane needs the orchestrator, then print one verdict
# line plus whatever is needed to act on it, and exit.
#
#   herdr-await.sh <pane> <report.json> [timeout-minutes, default 45]
#
# Run it with the Bash tool's run_in_background: the harness re-invokes the
# orchestrator when it exits, so nobody has to poll or remind anyone.
#
# Verdicts (first line of stdout) and exit codes:
#   REPORT   0  report file written and the agent has stopped working
#   BLOCKED  3  agent is waiting on an approval or a question
#   NOREPORT 4  agent went idle/exited without writing the report
#   QUOTA    5  usage/rate limit hit (Codex: flip axis 2 to fail)
#   GONE     6  pane or agent disappeared
#   TIMEOUT  124
set -uo pipefail

pane=${1:?pane} report=${2:?report} limit=$(( ${3:-45} * 60 ))
start=$(date +%s) seen_working=0 quiet_since=

screen() { herdr agent read "$pane" --source visible --format text 2>/dev/null | tail -n "${1:-40}"; }
finish() { # verdict code
  echo "$1 pane=$pane report=$report elapsed=$(( $(date +%s) - start ))s"
  if [ "$1" = REPORT ]; then
    jq '{status, summary, files_changed, blockers, concerns}' "$report" 2>/dev/null || cat "$report"
  else
    echo "--- screen ---"; screen 40
  fi
  exit "$2"
}
quota() { screen 60 | grep -qiE 'usage limit|rate limit (reached|exceeded)|quota|limit reached|upgrade to'; }

while :; do
  now=$(date +%s)
  [ $(( now - start )) -ge "$limit" ] && finish TIMEOUT 124
  st=$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // "gone"' 2>/dev/null) || st=gone
  [ -n "$st" ] || st=gone

  if [ "$st" != working ] && jq -e . "$report" >/dev/null 2>&1; then
    finish REPORT 0
  fi
  case "$st" in
    working) seen_working=1 quiet_since= ;;
    blocked) quota && finish QUOTA 5; finish BLOCKED 3 ;;
    gone)    finish GONE 6 ;;
    *)  # idle / done / unknown: the prompt may not have landed yet, and a
        # report can trail the last turn by a moment, so allow a grace window.
        if [ "$seen_working" = 1 ] || [ $(( now - start )) -ge 60 ]; then
          quiet_since=${quiet_since:-$now}
          if [ $(( now - quiet_since )) -ge 20 ]; then
            quota && finish QUOTA 5
            finish NOREPORT 4
          fi
        fi ;;
  esac
  sleep 3
done
