#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: nixidy-bootstrap [--help]

Equivalent to:
  nixidy bootstrap .#local-k3d | kubectl apply -f -

Transitions Phase 3 (kluctl-driven) infrastructure to Phase 4 (ArgoCD
app-of-apps). ArgoCD must already be Available before invoking, and it
must have credentials to access the local-k3d manifest repo referenced
by the rendered Application CR.
EOF
    exit 0
    ;;
esac

nixidy bootstrap .#local-k3d | kubectl apply -f -
