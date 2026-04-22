#!/usr/bin/env bash
# shellcheck shell=bash
# Build nixidy manifests then push them to the local-k3d private repo.
# Composition of `nixidy-build` followed by `nixidy-push`; both live on
# PATH as writeShellApplication-wrapped commands supplied via
# runtimeInputs in nixidy-sync.nix.
#
# Usage:
#   nixidy-sync [--help]
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: nixidy-sync [--help]

Runs `nixidy-build` then `nixidy-push` in-process (no just/nix run
indirection). Requires the same preconditions as the two sub-apps:

  - A configured LOCAL_K3D_REPO directory with a git remote
  - A current directory writable to receive ./result (nixidy-build)
  - An ARGOCD_REPO_URL env override when building for file:/// manifests

See `nixidy-build --help` and `nixidy-push --help` for details.
EOF
    exit 0
    ;;
esac

nixidy-build
nixidy-push
