#!/usr/bin/env bash
# shellcheck shell=bash
# Build nixidy-rendered Kubernetes manifests for the local-k3d env into
# ./result. Equivalent to `nixidy build .#local-k3d`; preserved here so
# the invocation is packaged as a first-class flake app for CI effects
# and justfile wrappers.
#
# Usage:
#   nixidy-build [--help]
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: nixidy-build [--help]

Invokes `nixidy build .#local-k3d`, producing a ./result/ symlink at the
working directory that materializes the rendered manifest tree.
ARGOCD_REPO_URL may be set in the environment to override the default
remote repo URL baked into the rendered Application resources (see
modules/nixidy.nix and the ARGOCD_REPO_URL env hook in kubernetes/nixidy).
EOF
    exit 0
    ;;
esac

exec nixidy build .#local-k3d
