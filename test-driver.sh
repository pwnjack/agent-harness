#!/usr/bin/env bash
# test.sh hands its suites a clean Herdr environment, whatever it inherited.
set -uo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; fail=1; }

mkdir -p -- "$tmp/clone"
cp -- "$repo/test.sh" "$tmp/clone/test.sh"
cat > "$tmp/clone/test-env.sh" <<'SH'
#!/usr/bin/env bash
env | grep -E '^(HERDR_CONFIG_PATH|HERDR_PANE_ID|HERDR_SOCKET_PATH|HARNESS_ROLE|HARNESS_SIDEBAR_SYNC)=' > "$TEST_DRIVER_ENV"
exit 0
SH
git -C "$tmp/clone" init -q && git -C "$tmp/clone" add test.sh test-env.sh || exit 1

TEST_DRIVER_ENV="$tmp/seen" HERDR_CONFIG_PATH="$tmp/sentinel.toml" HERDR_PANE_ID=w1:p1 \
  HERDR_SOCKET_PATH="$tmp/herdr.sock" HARNESS_ROLE=worker HARNESS_SIDEBAR_SYNC=1 \
  bash "$tmp/clone/test.sh" > "$tmp/output" 2>&1
if [ -f "$tmp/seen" ] && [ ! -s "$tmp/seen" ]; then ok 'suites see no inherited Herdr variables'
else no 'suites see no inherited Herdr variables'; cat -- "$tmp/seen" "$tmp/output" 2>/dev/null; fi
exit "$fail"
