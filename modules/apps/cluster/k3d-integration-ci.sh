#!/usr/bin/env bash
# shellcheck shell=bash
# CI integration driver for the local-k3d cluster. Uses the local
# file:///manifests repo URL (no GitHub credentials required) and
# orchestrates the full seven-phase flow consumed by
# .github/workflows/test-cluster.yaml's `integration` job.
#
# Usage:
#   k3d-integration-ci [--help]
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-integration-ci [--help]

Phases:
  1. nixidy-build with ARGOCD_REPO_URL=file:///manifests
  2. Stage /tmp/k3d-manifests as a fresh git repo (cluster volume mount target)
  3. k3d-full (ctlptl create + kluctl deploy)
  4. k3d-wait-ready (foundation + infra Ready)
  5. nixidy-bootstrap (app-of-apps sync via file:///manifests)
  6. k3d-wait-argocd-sync (all Applications Synced + Healthy)
  7. k3d-test-coverage (chainsaw tests + coverage report)

Must be invoked from a directory inside the vanixiets git worktree.
EOF
    exit 0
    ;;
esac

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

echo "=== Phase 1: Build manifests with local repo URL ==="
export ARGOCD_REPO_URL="file:///manifests"
just nixidy-build

echo ""
echo "=== Phase 2: Prepare local git repo (before cluster for volume mount) ==="
# Ensure writable before cleanup (Nix store copies may be read-only)
chmod -R +w /tmp/k3d-manifests 2>/dev/null || true
rm -rf /tmp/k3d-manifests
mkdir -p /tmp/k3d-manifests
rsync -aL --delete --chmod=Du+w,Fu+w result/ /tmp/k3d-manifests/
(
  cd /tmp/k3d-manifests
  git init -b main
  git config user.email "ci@localhost"
  git config user.name "CI"
  git add .
  git commit -m "CI manifests"
)

echo ""
echo "=== Phase 3: Create cluster and deploy via kluctl ==="
just k3d-full

echo ""
echo "=== Phase 4: Wait for infrastructure ready ==="
just k3d-wait-ready

echo ""
echo "=== Phase 5: Bootstrap ArgoCD (syncs from file:///manifests) ==="
just nixidy-bootstrap

echo ""
echo "=== Phase 6: Wait for ArgoCD sync ==="
just k3d-wait-argocd-sync

echo ""
echo "=== Phase 7: Run integration tests ==="
just k3d-test-coverage

echo ""
echo "=== CI integration complete ==="
