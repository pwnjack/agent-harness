#!/usr/bin/env bash
# Merge the tracked Codex settings fragments (codex/*.toml) into
# ~/.codex/config.toml with lib/toml-merge.sh, key by key, leaving everything
# else in that file alone. A no-op when Codex is not installed.
set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$src_dir/.." && pwd)"
target="${CODEX_HOME:-$HOME/.codex}/config.toml"

[ -d "$(dirname "$target")" ] || { echo "codex: not installed, skipping"; exit 0; }
exec bash "$repo/lib/toml-merge.sh" codex "$target" "$src_dir"/*.toml
