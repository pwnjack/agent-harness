#!/usr/bin/env bash
# Exercise brain commits and pushes using disposable repositories only.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=brain GIT_AUTHOR_EMAIL=brain@localhost
export GIT_COMMITTER_NAME=brain GIT_COMMITTER_EMAIL=brain@localhost
mkdir -p -- "$tmp/bin" || exit 1
for command in systemctl uname gh; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command" || exit 1
done
printf '#!/usr/bin/env bash\nprintf "claude: current\\ncodex: current\\n"\n' > "$tmp/bin/herdr" || exit 1
printf '#!/usr/bin/env bash\nexit "${SSH_ADD_RESULT:-0}"\n' > "$tmp/bin/ssh-add" || exit 1
chmod +x -- "$tmp"/bin/* || exit 1
export PATH="$tmp/bin:$PATH"
fail=0
number=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }
fixture() {
  number=$((number + 1))
  case_dir="$tmp/case-$number"
  export HOME="$case_dir/home" CLAUDE_CONFIG_DIR="$case_dir/claude" CODEX_HOME="$case_dir/codex"
  export XDG_STATE_HOME="$case_dir/state" XDG_CONFIG_HOME="$case_dir/config"
  export SSH_ADD_RESULT=0
  projects="$case_dir/projects"
  remote="$case_dir/remote.git"
  memory="$projects/-home-u-proj/memory"
  mkdir -p -- "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$memory" || exit 1
  git init -q -b main --bare -- "$remote" || exit 1
  git init -q -b main --separate-git-dir "$XDG_STATE_HOME/agent-brain.git" -- "$projects" || exit 1
  git -C "$projects" config brain.enabled true || exit 1
  git -C "$projects" config brain.remote "$remote" || exit 1
  git -C "$projects" remote add origin "$remote" || exit 1
  # During RED the template does not exist yet; use the specified whitelist.
  if [ -f "$here/gitignore" ]; then cp -- "$here/gitignore" "$projects/.gitignore"
  else
    printf '%s\n' '/*' '!/.gitignore' '!/*/' '/-tmp*/' '/*/*' '!/*/memory/' \
      '/*/memory/**' '!/*/memory/**/' '!/*/memory/**/*.md' '/*/memory/**/.*' > "$projects/.gitignore"
  fi
  printf '%s\n' '- [Note](note.md)' > "$memory/MEMORY.md"
  printf 'A harmless memory.\n' > "$memory/note.md"
}
run() {
  result=0
  bash "$here/commit.sh" "$projects" > "$case_dir/stdout" 2> "$case_dir/stderr" || result=$?
}
head_oid() { git -C "$projects" rev-parse -q --verify HEAD 2>/dev/null; }
remote_oid() { git --git-dir="$remote" rev-parse -q --verify refs/heads/main 2>/dev/null; }
count() { git -C "$projects" rev-list --count HEAD 2>/dev/null; }
tracked() { git -C "$projects" cat-file -e "HEAD:$1" 2>/dev/null; }

fixture
projects="$case_dir/missing"
run
if [ "$result" -eq 0 ] && [ ! -s "$case_dir/stderr" ]; then ok 'missing repo: quiet exit 0'
else no 'missing repo: quiet exit 0'; fi

fixture
git -C "$projects" config brain.enabled false
run
if [ "$result" -eq 0 ] && ! head_oid >/dev/null && [ ! -s "$case_dir/stderr" ]; then ok 'disabled: quiet exit 0, no commit'
else no 'disabled: quiet exit 0, no commit'; fi

for whitelist_state in missing altered; do
  fixture
  export SSH_ADD_RESULT=1
  run
  before=$(head_oid)
  export SSH_ADD_RESULT=0
  printf 'Private transcript.\n' > "$projects/-home-u-proj/transcript.jsonl"
  printf 'Consolidation state.\n' > "$memory/.consolidate-lock"
  printf 'Updated memory.\n' >> "$memory/note.md"
  if [ "$whitelist_state" = missing ]; then
    rm -- "$projects/.gitignore"
  else
    sed '1d' "$projects/.gitignore" > "$case_dir/altered-ignore"
    mv -- "$case_dir/altered-ignore" "$projects/.gitignore"
  fi
  run
  if [ "$result" -eq 1 ] && [ -n "$before" ] && [ "$(head_oid)" = "$before" ] \
     && [ -z "$(remote_oid)" ] && [ ! -s "$case_dir/stdout" ] \
     && [ "$(cat -- "$case_dir/stderr")" = 'brain: refusing missing or altered .gitignore whitelist' ]; then
    ok ".gitignore $whitelist_state: exit 1, no new commit, nothing pushed, one log line"
  else no ".gitignore $whitelist_state: exit 1, no new commit, nothing pushed, one log line"; fi
done

fixture
run
if [ "$result" -eq 0 ] && tracked .gitignore && tracked -home-u-proj/memory/note.md \
   && [ "$(git -C "$projects" log -1 --format='%an <%ae> %cn <%ce>')" = 'brain <brain@localhost> brain <brain@localhost>' ] \
   && [ "$(git -C "$projects" log -1 --format=%s)" = 'memory: -home-u-proj .gitignore' ]; then
  ok 'unborn HEAD: commits whitelist and memory with brain identity and changed keys'
else no 'unborn HEAD: commits whitelist and memory with brain identity and changed keys'; fi
if [ "$result" -eq 0 ] && [ -n "$(head_oid)" ] && [ "$(head_oid)" = "$(remote_oid)" ] \
   && [ "$(git -C "$projects" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" = origin/main ]; then
  ok 'first push: empty remote receives main and upstream is set'
else no 'first push: empty remote receives main and upstream is set'; fi

fixture
mkdir -p -- "$memory/nested/deeper" "$memory/.hidden" "$projects/-tmp-case/memory"
printf 'Nested.\n' > "$memory/nested/deeper/-some note.md"
for path in '-home-u-proj/transcript.jsonl' '-home-u-proj/memory/.consolidate-lock' \
  '-home-u-proj/memory/.hidden.md' '-home-u-proj/memory/.hidden/note.md' \
  '-home-u-proj/memory/notes.txt' '-tmp-case/memory/note.md' '.env'; do
  printf 'Private non-memory content.\n' > "$projects/$path"
done
run
if [ "$result" -eq 0 ] && [ "$(git -C "$projects" ls-tree -r --name-only HEAD 2>/dev/null | wc -l)" -eq 4 ] \
   && tracked '-home-u-proj/memory/nested/deeper/-some note.md'; then
  ok 'whitelist: nested markdown only; transcripts, locks, dotfiles, tmp projects and other files excluded'
else no 'whitelist: nested markdown only; transcripts, locks, dotfiles, tmp projects and other files excluded'; fi

fixture
printf 'Transcript.\n' > "$projects/-home-u-proj/transcript.jsonl"
git -C "$projects" add -f -- -home-u-proj/transcript.jsonl
index_before=$(git -C "$projects" write-tree)
run
if [ "$result" -eq 0 ] && tracked -home-u-proj/memory/note.md && ! tracked -home-u-proj/transcript.jsonl \
   && [ "$(git -C "$projects" write-tree)" = "$index_before" ]; then
  ok 'pre-staged transcript: excluded and shared index preserved'
else no 'pre-staged transcript: excluded and shared index preserved'; fi

fixture
printf 'Transcript.\n' > "$projects/-home-u-proj/transcript.jsonl"
git -C "$projects" add -f -- .gitignore -home-u-proj/transcript.jsonl
git -C "$projects" -c core.hooksPath=/dev/null commit -qm 'brain: fixture'
before=$(head_oid)
run
if [ "$result" -eq 1 ] && [ "$(head_oid)" = "$before" ] && [ -z "$(remote_oid)" ] \
   && grep -q '^brain: .*ignored' "$case_dir/stderr"; then ok 'force-added transcript in HEAD: refused'
else no 'force-added transcript in HEAD: refused'; fi

fixture
run
rm -- "$memory/note.md"
printf 'No entries.\n' > "$memory/MEMORY.md"
run
if [ "$result" -eq 0 ] && [ "$(count)" = 2 ] && ! tracked -home-u-proj/memory/note.md; then
  ok 'deleted memory: deletion committed'
else no 'deleted memory: deletion committed'; fi

fixture
run
before=$(head_oid)
secret='sk-abcdefghijklmnopqrstuvwxyz012345'
printf '%s\n' "$secret" >> "$memory/note.md"
run
if [ "$result" -eq 1 ] && [ "$(head_oid)" = "$before" ] \
   && grep -q '^brain: .*note.md.*openai' "$case_dir/stderr" \
   && ! grep -Fq -- "$secret" "$case_dir/stderr"; then ok 'secret: no commit and value absent from stderr'
else no 'secret: no commit and value absent from stderr'; fi

while IFS=$'\t' read -r name secret; do
  fixture
  printf '%s\n' "$secret" >> "$memory/note.md"
  run
  if [ "$result" -eq 1 ] && ! head_oid >/dev/null && [ -z "$(remote_oid)" ] \
     && grep -Fq -- "secret ($name)" "$case_dir/stderr" \
     && ! grep -Fq -- "$secret" "$case_dir/stderr"; then
    ok "secret ($name): unborn commit refused without exposing value"
  else no "secret ($name): unborn commit refused without exposing value"; fi
done <<'SECRETS'
anthropic	sk-ant-abcdefghijklmnopqrstuvwxyz012345
github	ghp_abcdefghijklmnopqrstuvwxyz012345
github-pat	github_pat_abcdefghijklmnopqrstuvwxyz012345
google	AIzaabcdefghijklmnopqrstuvwxyz012345678
aws	AKIAABCDEFGHIJKLMNOP
slack	xoxb-abcdefghijklmnop
private-key	-----BEGIN RSA PRIVATE KEY-----
assignment	SERVICE_TOKEN = 'abcdefghijklmnop012345'
SECRETS

fixture
run
before=$(head_oid)
run
if [ "$result" -eq 0 ] && [ "$(head_oid)" = "$before" ]; then ok 'no changes: exit 0, no new commit'
else no 'no changes: exit 0, no new commit'; fi

fixture
printf 'Unindexed.\n' > "$memory/unlisted.md"
run
if [ "$result" -eq 0 ] && tracked -home-u-proj/memory/unlisted.md \
   && grep -Fq -- 'brain: ERROR -home-u-proj/memory/unlisted.md: not in MEMORY.md' "$case_dir/stderr"; then
  ok 'audit ERROR: logged without blocking the commit'
else no 'audit ERROR: logged without blocking the commit'; fi

fixture
git init -q -b main --bare -- "$case_dir/wrong.git"
git -C "$projects" remote set-url --push origin "$case_dir/wrong.git"
run
if [ "$result" -eq 1 ] && [ -z "$(remote_oid)" ] \
   && ! git --git-dir="$case_dir/wrong.git" rev-parse -q --verify HEAD >/dev/null; then
  ok 'changed pushurl: refuses to push'
else no 'changed pushurl: refuses to push'; fi

fixture
git init -q -b main --bare -- "$case_dir/wrong.git"
git -C "$projects" config --add remote.origin.pushurl "$remote"
git -C "$projects" config --add remote.origin.pushurl "$case_dir/wrong.git"
run
if [ "$result" -eq 1 ] && [ -z "$(remote_oid)" ] \
   && ! git --git-dir="$case_dir/wrong.git" rev-parse -q --verify HEAD >/dev/null; then
  ok 'additional pushurl: refuses all destinations'
else no 'additional pushurl: refuses all destinations'; fi

for ssh_result in 1 2; do
  fixture
  export SSH_ADD_RESULT=$ssh_result
  run
  if [ "$result" -eq 0 ] && [ "$(count)" = 1 ] && [ -z "$(remote_oid)" ] \
     && grep -q '^brain: push deferred' "$case_dir/stderr"; then
    ok "ssh-add exit $ssh_result: commit made, push deferred"
  else no "ssh-add exit $ssh_result: commit made, push deferred"; fi
done

fixture
mv -- "$remote" "$case_dir/saved.git"
run
before=$(head_oid)
if [ "$result" -eq 1 ] && [ "$(count)" = 1 ] && grep -q '^brain: push failed' "$case_dir/stderr"; then
  ok 'unreachable remote with key: commit made, exit 1'
else no 'unreachable remote with key: commit made, exit 1'; fi
mv -- "$case_dir/saved.git" "$remote"
run
if [ "$result" -eq 0 ] && [ -n "$before" ] && [ "$(head_oid)" = "$before" ] && [ "$(remote_oid)" = "$before" ]; then
  ok 'failed push: next run without changes retries successfully'
else no 'failed push: next run without changes retries successfully'; fi

fixture
run
mv -- "$remote" "$case_dir/saved.git"
printf 'Updated memory.\n' >> "$memory/note.md"
run
before=$(head_oid)
if [ "$result" -eq 1 ] && [ "$(count)" = 2 ]; then
  ok 'established upstream: changed memory committed despite failed push'
else no 'established upstream: changed memory committed despite failed push'; fi
mv -- "$case_dir/saved.git" "$remote"
run
if [ "$result" -eq 0 ] && [ -n "$before" ] && [ "$(head_oid)" = "$before" ] && [ "$(remote_oid)" = "$before" ]; then
  ok 'established upstream: unchanged run pushes outstanding commit'
else no 'established upstream: unchanged run pushes outstanding commit'; fi

fixture
git -C "$projects" config commit.gpgsign true
git -C "$projects" config gpg.program "$case_dir/nonexistent-gpg"
mkdir -p -- "$case_dir/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$case_dir/hooks/pre-commit"
chmod +x -- "$case_dir/hooks/pre-commit"
git -C "$projects" config core.hooksPath "$case_dir/hooks"
run
if [ "$result" -eq 0 ] && [ "$(count)" = 1 ] && [ "$(head_oid)" = "$(remote_oid)" ]; then
  ok 'commit-tree: signing configuration and failing hooks cannot prompt or block'
else no 'commit-tree: signing configuration and failing hooks cannot prompt or block'; fi

exit "$fail"
