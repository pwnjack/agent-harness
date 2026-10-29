#!/usr/bin/env bash
# apply-config.sh merges the Card layout into Herdr's config and rolls back on a failed check.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
real_herdr=$(command -v herdr 2>/dev/null || true)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$tmp/bin" "$tmp/nobin"
for command in systemctl uname gh ssh-add; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
done
cat > "$tmp/bin/herdr" <<EOS
#!/usr/bin/env bash
line=\$1; shift
for arg in "\$@"; do line="\$line|\$arg"; done
printf '%s\n' "\$line" >> '$tmp/calls'
case \$line in
  config\|check)
    if [ "\${CHECK_RC:-0}" = 0 ]; then echo 'config: ok'; else echo 'config: issues found'; fi
    exit "\${CHECK_RC:-0}" ;;
  status\|server) exit "\${SERVER_RC:-0}" ;;
esac
exit 0
EOS
chmod +x -- "$tmp"/bin/*
for tool in bash awk sed mktemp cp rm cat dirname basename mkdir cmp grep; do
  ln -s -- "$(command -v "$tool")" "$tmp/nobin/$tool"
done
export PATH="$tmp/bin:$PATH"
unset HERDR_CONFIG_PATH CHECK_RC SERVER_RC
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
apply="$here/apply-config.sh"
default="$XDG_CONFIG_HOME/herdr/config.toml"
live() {
  mkdir -p -- "${default%/*}"
  printf 'onboarding = false\n\n# keep me\n[keys]\nprefix = "ctrl+b"\n' > "$default"
}

live; : > "$tmp/calls"
out=$(bash "$apply" 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -qx 'onboarding = false' "$default" && grep -qx '# keep me' "$default" \
   && grep -qx 'prefix = "ctrl+b"' "$default" && grep -q 'sidebar_width = 34' "$default" \
   && grep -q '\$effort' "$default" && grep -q 'herdr: merged' <<<"$out"; then
  ok 'merge keeps unrelated keys and comments'
else no 'merge keeps unrelated keys and comments'; fi
if grep -qx 'config|check' "$tmp/calls" && grep -qx 'server|reload-config' "$tmp/calls" \
   && grep -q 'herdr: reloaded config' <<<"$out"; then ok 'checked and reloaded'; else no 'checked and reloaded'; fi
ls "$default".* >/dev/null 2>&1 && no 'backup removed' || ok 'backup removed'

cp -- "$default" "$tmp/first"
out=$(bash "$apply" 2>&1)
if cmp -s "$default" "$tmp/first" && grep -q 'already up to date' <<<"$out"; then ok 'second run byte-identical'
else no 'second run byte-identical'; fi

live; cp -- "$default" "$tmp/before"; : > "$tmp/calls"
out=$(CHECK_RC=1 bash "$apply" 2>&1); rc=$?
if [ "$rc" = 1 ] && cmp -s "$default" "$tmp/before" && grep -q "herdr: config check failed; restored $default" <<<"$out" \
   && grep -q 'config: issues found' <<<"$out" && ! grep -q reload-config "$tmp/calls"; then ok 'failing check restores the original'
else no 'failing check restores the original'; fi
ls "$default".* >/dev/null 2>&1 && no 'backup removed after failure' || ok 'backup removed after failure'

rm -f -- "$default"; mkdir -p -- "$tmp/custom"; : > "$tmp/calls"
out=$(HERDR_CONFIG_PATH="$tmp/custom/c.toml" bash "$apply" 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -q 'sidebar_width = 34' "$tmp/custom/c.toml" && [ ! -e "$default" ] \
   && grep -qx 'config|check' "$tmp/calls" && grep -qx 'server|reload-config' "$tmp/calls"; then
  ok 'HERDR_CONFIG_PATH is merged, checked and reloaded'
else no 'HERDR_CONFIG_PATH is merged, checked and reloaded'; fi

live
printf '\n[ui.sidebar.agents.rows_by_agent]\nclaude = [["state_icon"]]\n' >> "$default"
out=$(bash "$apply" 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -q "herdr: warning: rows_by_agent.claude in $default replaces the Card layout for claude" <<<"$out" \
   && ! grep -q 'rows_by_agent.codex' <<<"$out" && grep -q '^claude = ' "$default"; then
  ok 'rows_by_agent.claude warns and survives'
else no 'rows_by_agent.claude warns and survives'; fi

live; : > "$tmp/calls"
out=$(SERVER_RC=1 bash "$apply" 2>&1); rc=$?
if [ "$rc" = 0 ] && ! grep -q reload-config "$tmp/calls" && ! grep -q 'reloaded' <<<"$out"; then ok 'reload only when server answers'
else no 'reload only when server answers'; fi

live; cp -- "$default" "$tmp/before"
out=$(PATH="$tmp/nobin" "$BASH" "$apply" 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -qx 'herdr: not installed, skipping' <<<"$out" && cmp -s "$default" "$tmp/before"; then
  ok 'not installed: skipped, exit 0'
else no 'not installed: skipped, exit 0'; fi

if [ -n "$real_herdr" ]; then
  if cp -- "$here/sidebar.toml" "$tmp/real.toml" \
     && HERDR_CONFIG_PATH="$tmp/real.toml" "$real_herdr" config check >/dev/null 2>&1; then ok 'real layout validates'
  else no 'real layout validates'; fi
else
  ok 'real layout validates (skipped: no herdr)'
fi
exit "$fail"
