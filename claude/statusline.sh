#!/usr/bin/env bash
# Claude Code status line — model, effort, context, prompt cache, 5h/7d rate
# limits with the weekly pace.
# Adapted from https://github.com/fedddorov/claude-code-status-bar (MIT).
# Wire up in ~/.claude/settings.json:
#   "statusLine": {"type": "command", "command": "bash ~/.claude/harness/claude/statusline.sh"}
# The session's time locale, kept for naming reset days before LC_ALL=C below.
time_locale=${LC_ALL:-${LC_TIME:-${LANG:-C}}}
export LC_ALL=C   # Use the C locale for numeric formatting.
input=$(cat)
IFS=$'\x1f' read -r model effort cwd used total win cache_seen cache_warm cache_at cache_cold_tok \
  fiveh fiveh_at week week_at < <(
  jq -r '[
    (.model.display_name // "" | sub(" *\\(.*\\)$"; "")),
    (.effort.level // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.used_percentage // ""),
    (.context_window | if .total_input_tokens == null and .total_output_tokens == null then ""
       else (.total_input_tokens // 0) + (.total_output_tokens // 0) end),
    (.context_window.context_window_size // 0 | if . > 0 then floor else "" end),
    (if .prompt_cache.caching_observed == true then 1 else "" end),
    (if .prompt_cache.warm == true then 1 else "" end),
    (.prompt_cache.expires_at // ""),
    (.prompt_cache.recache_tokens_if_cold // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("\u001f")' <<<"$input"
)

# Feed the herdr sidebar; the reporter detaches its own Herdr call.
reporter="$(dirname "${BASH_SOURCE[0]}")/../herdr/sidebar-report.sh"
bash "$reporter" "$cwd" "$model" "$effort" claude </dev/null >/dev/null 2>&1 || true

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
BLU=$'\033[38;5;110m'   # soft steel blue: context's base, apart from the usage bars
MAG=$'\033[38;5;140m'   # muted purple
# rate-limit color: green < 50, yellow >= 50, orange >= 80, red >= 90
hue() { awk -v p="$1" -v g="$GRN" -v y="$YEL" -v o="$ORG" -v r="$RED" 'BEGIN{if(p>=90)print r;else if(p>=80)print o;else if(p>=50)print y;else print g}'; }
# context color: blue < 50, yellow >= 50, orange >= 70, red >= 85
hue_ctx() { awk -v p="$1" -v g="$BLU" -v y="$YEL" -v o="$ORG" -v r="$RED" 'BEGIN{if(p>=85)print r;else if(p>=70)print o;else if(p>=50)print y;else print g}'; }
# reasoning-effort color: green = low, yellow = medium, orange = high, red = xhigh, purple = max
hue_eff() { case "$1" in low) echo "$GRN";; medium) echo "$YEL";; high) echo "$ORG";; xhigh) echo "$RED";; max) echo "$MAG";; *) echo "$DIM";; esac; }
# prompt-cache color by seconds left before the prefix goes cold: green > 15 min, yellow > 5 min, orange after
hue_cache() { awk -v t="$1" -v now="$(date +%s)" -v g="$GRN" -v y="$YEL" -v o="$ORG" 'BEGIN{s=t-now;if(s>900)print g;else if(s>300)print y;else print o}'; }
# weekly-pace color: dim within 5 points of the elapsed week, yellow > 5 ahead, orange > 15 ahead
hue_pace() { awk -v d="$1" -v n="$DIM" -v y="$YEL" -v o="$ORG" 'BEGIN{if(d>15)print o;else if(d>5)print y;else print n}'; }

# FiraCode's own progress bar (U+EE00-EE05): an outlined, round-ended bar
# whose cells fill from the left. Empty left/middle/right, then filled
# left/middle/right, encoded as UTF-8 bytes.
PB=($'\xee\xb8\x80' $'\xee\xb8\x81' $'\xee\xb8\x82'
    $'\xee\xb8\x83' $'\xee\xb8\x84' $'\xee\xb8\x85')
BAR_CELLS=8

# bar <percent> <color>: the whole bar in one colour with a continuous outline.
# The cell count rounds percent/100*(n-0.6)+0.4 to the nearest integer,
# clamped to 0..n, with zero percent producing no filled cells.
bar() {
  local filled i k out=""
  filled=$(awk -v u="$1" -v n="$BAR_CELLS" 'BEGIN{f=int(u/100*(n-0.6)+0.4+0.5);if(u<=0)f=0;if(f<0)f=0;if(f>n)f=n;print f}')
  for ((i = 1; i <= BAR_CELLS; i++)); do
    if [ "$i" -eq 1 ]; then k=0; elif [ "$i" -eq "$BAR_CELLS" ]; then k=2; else k=1; fi
    [ "$i" -le "$filled" ] && k=$((k + 3))
    out+=${PB[$k]}
  done
  printf '%s%s%s' "$2" "$out" "$R"
}

# pie <percent> <color>: one cell for the context meter, a circle that fills
# clockwise in eighths: nf-md-circle_outline, then nf-md-circle_slice_1..8
# (U+F0766, U+F0A9E-F0AA5), encoded as UTF-8 bytes.
PIE=($'\xf3\xb0\x9d\xa6' $'\xf3\xb0\xaa\x9e' $'\xf3\xb0\xaa\x9f'
     $'\xf3\xb0\xaa\xa0' $'\xf3\xb0\xaa\xa1' $'\xf3\xb0\xaa\xa2'
     $'\xf3\xb0\xaa\xa3' $'\xf3\xb0\xaa\xa4' $'\xf3\xb0\xaa\xa5')
pie() {
  local k; k=$(awk -v u="$1" 'BEGIN{k=int(u/12.5+0.5);if(k<0)k=0;if(k>8)k=8;print k}')
  printf '%s%s%s' "$2" "${PIE[$k]}" "$R"
}

# prompt cache: nf-md-fire (U+F0238) while the cached prefix is warm,
# nf-md-snowflake (U+F0717) once it has gone cold, encoded as UTF-8 bytes.
FIRE=$'\xf3\xb0\x88\xb8'
SNOW=$'\xf3\xb0\x9c\x97'

# clock time of an epoch, with the weekday when it is not today; 12 h when
# options/clock says so, like the bar and the desktop clock
fmt_at() {
  local f='%H:%M'
  [ "$(cat "$HOME/.config/options/clock" 2>/dev/null)" = 12h ] && f='%-I:%M%p'
  [ "$(date -d "@$1" +%F)" = "$(date +%F)" ] || f="%a $f"
  LC_ALL=$time_locale date -d "@$1" +"$f"
}

# rate-limit segment: label, percent, reset epoch, pace delta (7d only)
limit() {
  local c; c=$(hue "$2")
  printf '%s%s%s %s %s%.0f%%%s' "$DIM" "$1" "$R" "$(bar "$2" "$c")" "$c" "$2" "$R"
  [ -n "$4" ] && printf ' %s%s%s' "$(hue_pace "$4")" "$4" "$R"
  [ -n "$3" ] && printf ' %s%s%s · %s%s' "$DIM" "${4:+· }" "$(fmt_left "$3")" "$(fmt_at "$3")" "$R"
}

# weekly pace: used percent minus the elapsed share of the 7-day window, as a
# signed whole number; +6 means usage runs six points ahead of the clock.
pace() {
  awk -v u="$1" -v t="$2" -v now="$(date +%s)" 'BEGIN{e=(1-(t-now)/604800)*100;if(e<0)e=0;if(e>100)e=100;d=u-e;if(d>-0.5&&d<0.5)d=0;printf"%+.0f",d}'
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
  cc=$(hue_ctx "$used")
  ctx="$(pie "$used" "$cc") ${cc}$(printf '%.0f' "$used")%${R}"
  [ -n "$total" ] && ctx="${ctx} ${B}$(fmt_tok "$total")${R}${win:+${DIM}/$(fmt_tok "$win")${R}}"
  parts+=("$ctx")
fi

# Prompt cache, once a response has reported cache tokens: the flame with the
# time until the prefix goes cold, or the snowflake with the tokens the next
# request re-caches. Booleans are compared in jq: its // would drop false. An
# expiry already behind us is cold, whatever the last render's warm said.
if [ -n "$cache_seen" ]; then
  if [ -n "$cache_warm" ] && [ -n "$cache_at" ] && [ "${cache_at%.*}" -gt "$(date +%s)" ] 2>/dev/null; then
    cc=$(hue_cache "$cache_at")
    parts+=("${cc}${FIRE}${R} ${cc}$(fmt_left "$cache_at")${R}")
  else
    parts+=("${BLU}${SNOW}${R}${cache_cold_tok:+ ${DIM}$(fmt_tok "$cache_cold_tok")${R}}")
  fi
fi

[ -n "$fiveh" ] && parts+=("$(limit 5h "$fiveh" "$fiveh_at")")
if [ -n "$week" ]; then
  wp=""; [ -n "$week_at" ] && wp=$(pace "$week" "$week_at")
  parts+=("$(limit 7d "$week" "$week_at" "$wp")")
fi

out=""
for p in "${parts[@]}"; do out="${out:+$out$sep}$p"; done
printf '%s\n' "$out"
