#!/usr/bin/env bash
# shellcheck shell=bash
# Full local-k3d lifecycle: tear down any existing cluster, recreate it,
# and deploy foundation + infrastructure layers. Delegates to the
# original just recipes (k3d-down, k3d-up, k3d-deploy) which remain the
# single source of truth for the cluster wiring during the M1 transition
# window.
#
# Usage:
#   k3d-full [--help]
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-full [--help]

Runs, in order:
  just k3d-down || true     (idempotent teardown)
  just k3d-up               (ctlptl apply + bootstrap-secrets)
  just k3d-deploy           (foundation + infrastructure layers)

The invocation must happen from a directory inside the vanixiets git
worktree (repo root resolution via `git rev-parse --show-toplevel`),
since the underlying just recipes reference
kubernetes/clusters/local-k3d/cluster.yaml by relative path.
EOF
    exit 0
    ;;
esac

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$repo_root" ]]; then
  cd "$repo_root"
fi

just k3d-down || true
just k3d-up
just k3d-deploy
