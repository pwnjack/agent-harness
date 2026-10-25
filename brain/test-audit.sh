#!/usr/bin/env bash
# Exercise the memory audit without reading machine state.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
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
projects="$CLAUDE_CONFIG_DIR/projects"
memory="$projects/-home-u-proj/memory"
fixture() {
  rm -rf -- "$projects"
  mkdir -p -- "$memory" "$projects/-home-u-other/memory" "$projects/-tmp/memory"
  printf '%s\n' '- [A memory](note.md) — a hook' > "$memory/MEMORY.md"
  printf 'A harmless memory.\n' > "$memory/note.md"
  : > "$projects/-home-u-other/memory/MEMORY.md"
}
audit() {
  result=0
  bash "$here/audit.sh" "$projects" "$@" > "$tmp/output" 2>&1 || result=$?
}
exact() { [ "$(cat -- "$tmp/output")" = "$1" ]; }

fixture
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok 'clean project: exit 0, no output'
else no 'clean project: exit 0, no output'; fi

fixture
printf 'A missed memory.\n' > "$memory/gtk4-blur-on-hyprland.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/gtk4-blur-on-hyprland.md: not in MEMORY.md'; then
  ok 'unindexed file: ERROR names it'
else no 'unindexed file: ERROR names it'; fi

fixture
printf '%s\n' '- [Missing](missing.md)' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/missing.md: missing file'; then
  ok 'index entry without file: ERROR names it'
else no 'index entry without file: ERROR names it'; fi

# Keep expectations independent of the patterns file so a missing rule fails.
while IFS=$'\t' read -r name value; do
  fixture
  printf '%s\n' "$value" >> "$memory/note.md"
  audit
  if [ "$result" -eq 1 ] \
     && grep -Fqx -- "ERROR -home-u-proj/memory/note.md: secret ($name)" "$tmp/output" \
     && ! grep -Fq -- "$value" "$tmp/output"; then
    ok "secret ($name): detected without exposing value"
  else no "secret ($name): detected without exposing value"; fi
done <<'SECRETS'
openai	sk-abcdefghijklmnopqrstuvwxyz012345
anthropic	sk-ant-abcdefghijklmnopqrstuvwxyz012345
github	ghp_abcdefghijklmnopqrstuvwxyz012345
github	gho_abcdefghijklmnopqrstuvwxyz012345
github-pat	github_pat_abcdefghijklmnopqrstuvwxyz012345
google	AIzaabcdefghijklmnopqrstuvwxyz012345678
aws	AKIAABCDEFGHIJKLMNOP
slack	xoxb-abcdefghijklmnop
slack	xoxa-abcdefghijklmnop
slack	xoxp-abcdefghijklmnop
private-key	-----BEGIN RSA PRIVATE KEY-----
assignment	SERVICE_TOKEN = 'abcdefghijklmnop012345'
SECRETS

fixture
printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/MEMORY.md: secret (openai)'; then
  ok 'index text is scanned for secrets'
else no 'index text is scanned for secrets'; fi

fixture
mkdir -p -- "$memory/.hidden" "$memory/nested"
printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' > "$memory/.consolidate-lock"
cp -- "$memory/.consolidate-lock" "$memory/.hidden.md"
cp -- "$memory/.consolidate-lock" "$memory/.hidden/hidden.md"
cp -- "$memory/.consolidate-lock" "$memory/nested/.hidden.md"
cp -- "$memory/.consolidate-lock" "$memory/notes.txt"
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok '.consolidate-lock, dotfiles, hidden directories and non-Markdown files: ignored'
else no '.consolidate-lock, dotfiles, hidden directories and non-Markdown files: ignored'; fi

fixture
mkdir -p -- "$projects/-tmp-another/memory"
printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' > "$projects/-tmp/memory/unindexed.md"
cp -- "$projects/-tmp/memory/unindexed.md" "$projects/-tmp-another/memory/unindexed.md"
audit
clean_result=$result
clean_output=$(cat -- "$tmp/output")
audit -tmp -tmp-another
if [ "$clean_result" -eq 0 ] && [ -z "$clean_output" ] \
   && [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok '-tmp projects: ignored in discovery and explicit selection'
else no '-tmp projects: ignored in discovery and explicit selection'; fi

fixture
printf 'Other memory.\n' > "$projects/-home-u-other/memory/unindexed.md"
audit -home-u-proj
selected_result=$result
selected_output=$(cat -- "$tmp/output")
audit -home-u-other
if [ "$selected_result" -eq 0 ] && [ -z "$selected_output" ] \
   && [ "$result" -eq 1 ] && exact 'ERROR -home-u-other/memory/unindexed.md: not in MEMORY.md'; then
  ok 'explicit project keys restrict the audit'
else no 'explicit project keys restrict the audit'; fi

fixture
mkdir -p -- "$memory/nested/deeper"
printf 'Nested memory.\n' > "$memory/nested/deeper/-some note.md"
printf '%s\n' '- [Nested](nested/deeper/-some note.md)' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok 'indexed nested file with spaces and a leading dash: clean'
else no 'indexed nested file with spaces and a leading dash: clean'; fi
printf 'Unindexed.\n' > "$memory/nested/unlisted.md"
printf '%s\n' '- [Missing](nested/deeper/missing.md)' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 1 ] \
   && grep -Fqx -- 'ERROR -home-u-proj/memory/nested/unlisted.md: not in MEMORY.md' "$tmp/output" \
   && grep -Fqx -- 'ERROR -home-u-proj/memory/nested/deeper/missing.md: missing file' "$tmp/output"; then
  ok 'nested index errors use paths relative to memory'
else no 'nested index errors use paths relative to memory'; fi

fixture
rm -- "$memory/MEMORY.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/note.md: not in MEMORY.md'; then
  ok 'missing index leaves content unindexed'
else no 'missing index leaves content unindexed'; fi

fixture
rm -- "$memory/note.md"
printf '%4096s' '' > "$memory/MEMORY.md"
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok 'MEMORY.md 4096 bytes: no warning'
else no 'MEMORY.md 4096 bytes: no warning'; fi
printf ' ' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 0 ] && exact 'WARN -home-u-proj/memory/MEMORY.md: over 4096 bytes'; then
  ok 'MEMORY.md 4097 bytes: WARN, exit 0'
else no 'MEMORY.md 4097 bytes: WARN, exit 0'; fi

fixture
printf 'Unindexed.\n' > "$memory/z.md"
printf 'Unindexed.\n' > "$memory/a.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/a.md: not in MEMORY.md
ERROR -home-u-proj/memory/z.md: not in MEMORY.md'; then
  ok 'diagnostics have deterministic path order'
else no 'diagnostics have deterministic path order'; fi

exit "$fail"
