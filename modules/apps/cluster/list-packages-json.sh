#!/usr/bin/env bash
# shellcheck shell=bash
# Resolves repo root via git rev-parse --show-toplevel.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: list-packages-json [--help]

Emit a JSON array of {"name": "<pkg>", "path": "packages/<pkg>"} for every
packages/<pkg>/ directory whose package.json declares a `release`
configuration (a non-null "release" key), the explicit opt-in to
semantic-release. Packages without one are never released. A package.json
that does not parse as a single JSON object is an error naming the file.
Consumed by the release-packages app
(modules/apps/release/release-packages.sh), which releases each listed path,
and exposed as `just list-packages-json`.

No positional arguments; must run inside a git worktree rooted at the
vanixiets repo (or subdirectory thereof).
EOF
    exit 0
    ;;
esac

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root/packages"

shopt -s nullglob
names=()
for manifest in */package.json; do
  pkg_name="${manifest%/package.json}"
  # Slurped so an empty file or trailing values fail instead of passing.
  if ! opted_in=$(jq -s '
    if length != 1 then error("expected exactly one JSON value")
    elif (.[0] | type) != "object" then error("expected a JSON object")
    else .[0].release != null end' "$manifest" 2>&1); then
    echo "list-packages-json: cannot parse packages/$manifest: $opted_in" >&2
    exit 1
  fi
  if [ "$opted_in" = true ]; then
    names+=("$pkg_name")
  fi
done

# Compact JSON array; the empty case is "[]".
jq -nc '$ARGS.positional | map({name: ., path: "packages/\(.)"})' --args "${names[@]}"
