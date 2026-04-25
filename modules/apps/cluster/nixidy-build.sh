#!/usr/bin/env bash
# shellcheck shell=bash
# Consumers: CI effects + justfile wrappers.
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
