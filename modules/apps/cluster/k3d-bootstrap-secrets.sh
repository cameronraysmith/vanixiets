#!/usr/bin/env bash
# shellcheck shell=bash
# Idempotent: reapplies cleanly and does not mutate the secret when the key source has not changed.
#
# Env-var contract:
#   One of the following MUST be satisfied (narrow exception; env-first):
#     SOPS_AGE_KEY                       (env)  single-line AGE-SECRET-KEY-…
#                                               body (CI / effect preamble)
#     $HOME/.config/sops/age/keys.txt    (file) local dev pathway
#
#   This is the ONLY flake app in modules/apps/ that intentionally consumes
#   SOPS_AGE_KEY directly. No other effect or app is permitted to expose
#   it. Rationale: the k3d bootstrap flow needs an age key INSIDE the
#   ephemeral cluster for sops-secrets-operator to decrypt SopsSecret CRs
#   at runtime — this is a load-bearing narrow exception.
#
#   Caller mechanisms:
#     - Local dev:    file-branch via $HOME/.config/sops/age/keys.txt
#     - GHA env:      GHA `env:` block with SOPS_AGE_KEY from repo secrets
#     - effect:       effect preamble extracts SOPS_AGE_KEY from
#                     HERCULES_CI_SECRETS_JSON and exports before invoking
#                     the transitive caller (k3d-integration-ci)
#
# NB: intentionally uses if-else ladder rather than `: "${VAR:?…}"` because
# the "try env, fall back to file" behaviour is the contract shape; a single
# `:?` guard cannot express the env-OR-file dual branch.
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

# Validate key source BEFORE any kubectl invocation so the failure surface
# points at the contract (SOPS_AGE_KEY env OR the keys.txt file) rather
# than an opaque kubectl/api error.
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

kubectl create namespace sops-secrets-operator \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic sops-age-key \
  --namespace=sops-secrets-operator \
  --from-file=age.key="$KEYFILE" \
  --dry-run=client -o yaml | kubectl apply -f -
