#!/usr/bin/env bash
# Claude Code status line — model, effort, context, 5h/7d rate limits.
# Adapted from https://github.com/fedddorov/claude-code-status-bar
# Wire up in ~/.claude/settings.json:
#   "statusLine": {"type": "command", "command": "bash ~/.config/claude/statusline.sh"}
export LC_ALL=C   # printf %f rejects "72.4" under comma-decimal locales
input=$(cat)
IFS=$'\x1f' read -r model effort used total win fiveh fiveh_at week week_at < <(
  jq -r '[
    (.model.display_name // "" | sub(" *\\(.*\\)$"; "")),
    (.effort.level // ""),
    (.context_window.used_percentage // ""),
    (.context_window | if .total_input_tokens == null and .total_output_tokens == null then ""
       else (.total_input_tokens // 0) + (.total_output_tokens // 0) end),
    (.context_window.context_window_size // 0 | if . > 0 then floor else "" end),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("\u001f")' <<<"$input"
)

fmt_tok() { awk -v n="$1" 'BEGIN{if(n>=1000000)printf"%.1fM",n/1000000;else if(n>=1000)printf"%.0fk",n/1000;else printf"%d",n}'; }
# seconds until an epoch timestamp, as 2d3h / 2h14m / 9m
fmt_left() { awk -v t="$1" -v now="$(date +%s)" 'BEGIN{s=t-now;if(s<0)s=0;d=int(s/86400);h=int(s%86400/3600);m=int(s%3600/60);if(d>0)printf"%dd%dh",d,h;else if(h>0)printf"%dh%dm",h,m;else printf"%dm",m}'; }

# ANSI palette
DIM=$'\033[2;37m'
B=$'\033[1m'
R=$'\033[0m'
GRN=$'\033[38;5;108m'   # soft sage green
YEL=$'\033[38;5;179m'   # muted gold
ORG=$'\033[38;5;173m'   # soft amber
RED=$'\033[38;5;167m'   # soft rose-red
# rate-limit color: green < 50, yellow >= 50, orange >= 80, red >= 90
hue() { awk -v p="$1" -v g="$GRN" -v y="$YEL" -v o="$ORG" -v r="$RED" 'BEGIN{if(p>=90)print r;else if(p>=80)print o;else if(p>=50)print y;else print g}'; }
# context color: green < 50, yellow >= 50, orange >= 70, red >= 85
hue_ctx() { awk -v p="$1" -v g="$GRN" -v y="$YEL" -v o="$ORG" -v r="$RED" 'BEGIN{if(p>=85)print r;else if(p>=70)print o;else if(p>=50)print y;else print g}'; }
# reasoning-effort color: green = low, yellow = medium, red = high/xhigh/max
hue_eff() { case "$1" in low) echo "$GRN";; medium) echo "$YEL";; high|xhigh|max) echo "$RED";; *) echo "$DIM";; esac; }

# 8-cell bar colored by fill level: bar <percent> <color>
bar() {
  local filled i out=""
  filled=$(awk -v u="$1" 'BEGIN{f=int(u/12.5+0.5);if(f<0)f=0;if(f>8)f=8;print f}')
  for i in 1 2 3 4 5 6 7 8; do
    if [ "$i" -le "$filled" ]; then out="${out}$2█"; else out="${out}${DIM}░"; fi
  done
  printf '%s%s' "$out" "$R"
}

# rate-limit segment: label, percent, reset epoch
limit() {
  local c; c=$(hue "$2")
  printf '%s%s%s %s %s%.0f%%%s' "$DIM" "$1" "$R" "$(bar "$2" "$c")" "$c" "$2" "$R"
  [ -n "$3" ] && printf ' %s%s%s' "$DIM" "$(fmt_left "$3")" "$R"
}

sep="${DIM} │ ${R}"
parts=()

head=""
[ -n "$model" ] && head="${B}${model}${R}"
if [ -n "$effort" ]; then
  ec=$(hue_eff "$effort")
  head="${head:+$head }${ec}●${R} ${ec}${effort}${R}"
fi
[ -n "$head" ] && parts+=("$head")

if [ -n "$used" ]; then
  ctx="${DIM}ctx${R} $(hue_ctx "$used")$(printf '%.0f' "$used")%${R}"
  [ -n "$total" ] && ctx="${ctx}  ${B}$(fmt_tok "$total")${R}${win:+${DIM}/$(fmt_tok "$win")${R}}"
  parts+=("$ctx")
fi

[ -n "$fiveh" ] && parts+=("$(limit 5h "$fiveh" "$fiveh_at")")
[ -n "$week" ]  && parts+=("$(limit 7d "$week" "$week_at")")

out=""
for p in "${parts[@]}"; do out="${out:+$out$sep}$p"; done
printf '%s\n' "$out"
