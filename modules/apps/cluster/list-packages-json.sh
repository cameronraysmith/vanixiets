#!/usr/bin/env bash
# shellcheck shell=bash
# Emit a JSON matrix entry per packages/<name>/ with a package.json.
#
# Usage:
#   list-packages-json [--help]
#
# Output: a single JSON array line of {name, path} objects on stdout.
# Resolves the repo root via `git rev-parse --show-toplevel`, so callers
# may invoke from any subdirectory of the vanixiets worktree.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: list-packages-json [--help]

Emit a JSON array of {"name": "<pkg>", "path": "packages/<pkg>"} for every
packages/<pkg>/ directory containing a package.json. Consumed by the
preview-release-version CI matrix in cd.yaml (set-variables job).

No positional arguments; must run inside a git worktree rooted at the
vanixiets repo (or subdirectory thereof).
EOF
    exit 0
    ;;
esac

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root/packages"

packages=()
for dir in */; do
  pkg_name="${dir%/}"
  if [ -f "${dir}package.json" ]; then
    packages+=("{\"name\":\"$pkg_name\",\"path\":\"packages/$pkg_name\"}")
  fi
done

# Emit a JSON array; empty case still produces a valid "[]".
(
  IFS=,
  echo "[${packages[*]}]"
)
