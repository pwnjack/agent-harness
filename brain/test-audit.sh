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

# Emulate jq's older raw-output writer, which stops at an embedded NUL.
export TEST_REAL_JQ
TEST_REAL_JQ=$(command -v jq)
cat > "$tmp/bin/jq" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${TEST_OLD_JQ:-0}" = 1 ]; then
  "$TEST_REAL_JQ" "$@" | tr -d '\000'
else
  exec "$TEST_REAL_JQ" "$@"
fi
SH
chmod +x -- "$tmp/bin/jq" || exit 1

fixture
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok 'clean project: exit 0, no output'
else no 'clean project: exit 0, no output'; fi

fixture
mkdir -p -- "$memory/nested"
printf 'token sk-%s\n' 'abcdefghijklmnopqrstuvwxyz' > "$memory/nested/MEMORY.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/nested/MEMORY.md: not in MEMORY.md
ERROR -home-u-proj/memory/nested/MEMORY.md: secret (openai)'; then
  ok 'nested MEMORY.md: indexed and scanned like any memory'
else no 'nested MEMORY.md: indexed and scanned like any memory'; cat -- "$tmp/output"; fi

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
printf '%8192s' '' > "$memory/note.md"
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok 'memory file 8192 bytes: no warning'
else no 'memory file 8192 bytes: no warning'; fi
printf ' ' >> "$memory/note.md"
audit
if [ "$result" -eq 0 ] && exact 'WARN -home-u-proj/memory/note.md: over 8192 bytes'; then
  ok 'memory file 8193 bytes: WARN, exit 0'
else no 'memory file 8193 bytes: WARN, exit 0'; fi

fixture
printf 'Unindexed.\n' > "$memory/z.md"
printf 'Unindexed.\n' > "$memory/a.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/a.md: not in MEMORY.md
ERROR -home-u-proj/memory/z.md: not in MEMORY.md'; then
  ok 'diagnostics have deterministic path order'
else no 'diagnostics have deterministic path order'; fi

fixture
export TEST_OLD_JQ=1
printf 'Unindexed.\n' > "$memory/a.md"
printf 'Unindexed.\n' > "$memory/"$'z\nlast.md'
printf 'Unindexed.\n' > "$projects/-home-u-other/memory/other.md"
audit -home-u-proj -home-u-other -home-u-proj
unset TEST_OLD_JQ
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-other/memory/other.md: not in MEMORY.md
ERROR -home-u-proj/memory/a.md: not in MEMORY.md
ERROR -home-u-proj/memory/z
last.md: not in MEMORY.md'; then
  ok 'older jq: all keys and newline-containing paths sorted and audited once'
else no 'older jq: all keys and newline-containing paths sorted and audited once'; fi

fixture
printf '%s\n' '[Web](https://example.org/guide.md) [Absolute](/docs/guide.md)' \
  '[Mail](mailto:guide.md) [Anchor](#guide.md)' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then
  ok 'external and anchor links: not memory files'
else no 'external and anchor links: not memory files'; fi

fixture
printf '%s\n' '[Missing](missing.md) [Again](./missing.md) [Again](missing.md)' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/missing.md: missing file'; then
  ok 'duplicate relative links: one diagnostic'
else no 'duplicate relative links: one diagnostic'; fi

fixture
audit -home-u-typo -home-u-proj
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-typo/memory/: missing memory directory'; then
  ok 'unknown explicit key: exit 1 and name the missing memory directory'
else no 'unknown explicit key: exit 1 and name the missing memory directory'; fi

fixture
printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' > "$tmp/linked.md"
ln -s -- "$tmp/linked.md" "$memory/linked.md"
printf '%s\n' '[Linked](linked.md)' >> "$memory/MEMORY.md"
audit
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/linked.md: secret (openai)'; then
  ok 'symlinked Markdown file: scanned for secrets'
else no 'symlinked Markdown file: scanned for secrets'; fi

for link_target in missing directory; do
  for link_path in linked.md unlisted.md MEMORY.md nested/MEMORY.md; do
    fixture
    if [ "$link_target" = directory ]; then mkdir -p -- "$memory/target"; fi
    if [ "$link_path" = MEMORY.md ]; then rm -f -- "$memory/MEMORY.md" "$memory/note.md"; fi
    mkdir -p -- "$(dirname -- "$memory/$link_path")"
    ln -s -- "$memory/target" "$memory/$link_path"
    if [ "$link_path" != MEMORY.md ] && [ "$link_path" != unlisted.md ]; then
      printf '[Linked](%s) [Again](./%s)\n' "$link_path" "$link_path" >> "$memory/MEMORY.md"
    fi
    audit
    if [ "$result" -eq 1 ] && exact "ERROR -home-u-proj/memory/$link_path: symlink target is not a regular file"; then
      ok "$link_target symlink $link_path: one clear diagnostic"
    else no "$link_target symlink $link_path: one clear diagnostic"; fi
  done
done

fixture
mkdir -p -- "$tmp/audit-copy"
cp -- "$here/audit.sh" "$tmp/audit-copy/audit.sh"
printf 'last\tLAST_PATTERN' > "$tmp/audit-copy/patterns"
printf 'LAST_PATTERN\n' >> "$memory/note.md"
result=0
bash "$tmp/audit-copy/audit.sh" "$projects" > "$tmp/output" 2>&1 || result=$?
if [ "$result" -eq 1 ] && exact 'ERROR -home-u-proj/memory/note.md: secret (last)'; then
  ok 'patterns file without final newline: last rule is scanned'
else no 'patterns file without final newline: last rule is scanned'; fi

for unreadable in note.md MEMORY.md; do
  fixture
  chmod 000 -- "$memory/$unreadable"
  printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' > "$memory/z.md"
  mkdir -p -- "$projects/-zz-later/memory"
  printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' > "$projects/-zz-later/memory/other.md"
  audit
  chmod 600 -- "$memory/$unreadable"
  if [ "$result" -eq 1 ] \
     && grep -Fqx -- "ERROR -home-u-proj/memory/$unreadable: cannot read file" "$tmp/output" \
     && grep -Fqx -- 'ERROR -home-u-proj/memory/z.md: secret (openai)' "$tmp/output" \
     && grep -Fqx -- 'ERROR -zz-later/memory/other.md: secret (openai)' "$tmp/output"; then
    ok "unreadable $unreadable: reported while remaining files and projects are scanned"
  else no "unreadable $unreadable: reported while remaining files and projects are scanned"; fi
done

fixture
export TEST_REAL_GREP
TEST_REAL_GREP=$(command -v grep)
cat > "$tmp/bin/grep" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  case "$arg" in */memory/note.md) exit 2 ;; esac
done
exec "$TEST_REAL_GREP" "$@"
SH
chmod +x -- "$tmp/bin/grep" || exit 1
printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' > "$memory/z.md"
audit
if [ "$result" -eq 1 ] \
   && grep -Fqx -- 'ERROR -home-u-proj/memory/note.md: secret scan failed (openai)' "$tmp/output" \
   && grep -Fqx -- 'ERROR -home-u-proj/memory/z.md: secret (openai)' "$tmp/output"; then
  ok 'failed file scan: reported while remaining files are scanned'
else no 'failed file scan: reported while remaining files are scanned'; fi

# A backticked home path that is gone is a warning; one that exists is not.
rm -f -- "$tmp/bin/grep"
fixture
mkdir -p -- "$HOME/kept"
printf 'See `~/kept` and `~/gone/file.md`, run `~/gone/tool <arg>`, glob `~/gone/?.md` `~/gone/[ab].md` `~/gone/*.md`.\n' > "$memory/note.md"
audit
if [ "$result" -eq 0 ] && exact 'WARN -home-u-proj/memory/note.md: cites missing ~/gone/file.md'; then
  ok 'cited home path: missing one warned; existing ones, commands and globs ignored'
else no 'cited home path: missing one warned; existing ones, commands and globs ignored'; fi

# --here: the main checkout's memory from a subdirectory or a linked worktree,
# the physical directory outside Git, and silence without a brain or a memory.
here_audit() { # directory
  result=0
  (cd -- "$1" && bash "$here/audit.sh" --here) > "$tmp/output" 2>&1 || result=$?
}
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# The audit skips keys that start with -tmp, so these checkouts live elsewhere.
work=$(mktemp -d /var/tmp/test-audit.XXXXXX) || exit 1
trap 'rm -rf -- "$tmp" "$work"' EXIT
mkdir -p -- "$work/repo.with_dots/sub/dir" "$work/plain"
git init -q -b main -- "$work/repo.with_dots" || exit 1
git -C "$work/repo.with_dots" -c user.name=T -c user.email=t@example.org commit -q --allow-empty -m fixture || exit 1
git -C "$work/repo.with_dots" worktree add -q --detach -- "$work/linked" || exit 1
root=$(cd -- "$work/repo.with_dots" && pwd -P)
key=$(printf '%s' "$root" | LC_ALL=C tr -c '[:alnum:]' '-')
plain=$(printf '%s' "$(cd -- "$work/plain" && pwd -P)" | LC_ALL=C tr -c '[:alnum:]' '-')
rm -rf -- "$projects"
mkdir -p -- "$projects/$key/memory"
printf 'unlisted\n' > "$projects/$key/memory/stray.md"
here_audit "$root/sub/dir"
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then ok '--here: silent without a brain'
else no '--here: silent without a brain'; fi
mkdir -p -- "$XDG_STATE_HOME/agent-brain.git"
for dir in "$root/sub/dir" "$work/linked"; do
  here_audit "$dir"
  if [ "$result" -eq 1 ] && exact "ERROR $key/memory/stray.md: not in MEMORY.md"; then
    ok "--here: audits the main checkout's memory from ${dir#"$work/"}"
  else no "--here: audits the main checkout's memory from ${dir#"$work/"}"; fi
done
here_audit "$work/plain"
if [ "$result" -eq 0 ] && [ ! -s "$tmp/output" ]; then ok '--here: silent without a memory directory'
else no '--here: silent without a memory directory'; fi
mkdir -p -- "$projects/$plain/memory"
printf 'unlisted\n' > "$projects/$plain/memory/stray.md"
here_audit "$work/plain"
if [ "$result" -eq 1 ] && exact "ERROR $plain/memory/stray.md: not in MEMORY.md"; then
  ok '--here: outside Git audits the physical directory'
else no '--here: outside Git audits the physical directory'; fi
(unset XDG_STATE_HOME; mkdir -p -- "$HOME/.local/state/agent-brain.git"; cd -- "$work/plain" && bash "$here/audit.sh" --here) > "$tmp/output" 2>&1 && result=0 || result=$?
if [ "$result" -eq 1 ]; then ok '--here: finds the brain under the default state directory'
else no '--here: finds the brain under the default state directory'; fi

exit "$fail"
