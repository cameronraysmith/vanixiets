#!/usr/bin/env bash
# shellcheck shell=bash
# Bootstrap the sops-age-key Kubernetes secret required by
# sops-secrets-operator to decrypt SopsSecret custom resources in the
# local-k3d cluster. Idempotent: reapplies cleanly and does not mutate
# the secret when the key source has not changed.
#
# Usage:
#   k3d-bootstrap-secrets [--help]
#
# Key sources (first one found wins):
#   SOPS_AGE_KEY env var       - used directly (CI pathway)
#   ~/.config/sops/age/keys.txt - file-based (local dev pathway)
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-bootstrap-secrets [--help]

Creates the sops-secrets-operator namespace (if missing) and the
sops-age-key secret containing an age private key used to decrypt
SopsSecret CRs. Idempotent: subsequent invocations leave the secret
byte-identical. Requires kubectl context pointing at the live k3d
cluster.

Key source (first found):
  SOPS_AGE_KEY                  environment variable (CI)
  ~/.config/sops/age/keys.txt   file (local dev)
EOF
    exit 0
    ;;
esac

kubectl create namespace sops-secrets-operator \
  --dry-run=client -o yaml | kubectl apply -f -

# Determine age key file: env var (CI) or local file (dev)
if [ -n "${SOPS_AGE_KEY:-}" ]; then
  echo "Using SOPS_AGE_KEY from environment variable"
  KEYFILE=$(mktemp)
  echo "${SOPS_AGE_KEY}" > "$KEYFILE"
  trap 'rm -f "$KEYFILE"' EXIT
else
  echo "Using SOPS age key from file: ${HOME}/.config/sops/age/keys.txt"
  KEYFILE="${HOME}/.config/sops/age/keys.txt"
  if [ ! -f "$KEYFILE" ]; then
    echo "error: age key file not found: $KEYFILE" >&2
    echo "  either set SOPS_AGE_KEY or create the file" >&2
    exit 1
  fi
fi

kubectl create secret generic sops-age-key \
  --namespace=sops-secrets-operator \
  --from-file=age.key="$KEYFILE" \
  --dry-run=client -o yaml | kubectl apply -f -
