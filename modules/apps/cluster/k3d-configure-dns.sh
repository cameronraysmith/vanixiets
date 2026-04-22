#!/usr/bin/env bash
# shellcheck shell=bash
# Patch the k3d cluster's CoreDNS to forward sslip.io queries to public
# DNS resolvers so ArgoCD Application routes using <ip>.sslip.io domains
# resolve inside the cluster. Idempotent: re-running on an
# already-configured cluster detects the existing "sslip.io" block and
# exits 0 without mutation.
#
# Usage:
#   k3d-configure-dns [--help]
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-configure-dns [--help]

Patches the kube-system/coredns ConfigMap to add a
  sslip.io:53 { forward . 1.1.1.1 8.8.8.8; cache 30 }
stanza, then rolls the coredns Deployment so the new Corefile takes
effect. Idempotent; re-running on an already-patched cluster is a no-op.

Requires kubectl context pointing at a running k3d cluster with
Cilium (or another CNI) already Ready.
EOF
    exit 0
    ;;
esac

echo "Waiting for CoreDNS to be running..."
kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=120s

echo "Patching CoreDNS ConfigMap to forward sslip.io to public DNS..."
CURRENT=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}')
if echo "$CURRENT" | grep -q "sslip.io"; then
  echo "CoreDNS already configured for sslip.io forwarding"
  exit 0
fi

SSLIP_BLOCK=$'sslip.io:53 {\n    forward . 1.1.1.1 8.8.8.8\n    cache 30\n}\n'
PATCHED="${SSLIP_BLOCK}${CURRENT}"
PATCH_JSON=$(jq -n --arg corefile "$PATCHED" '{"data": {"Corefile": $corefile}}')
kubectl patch configmap coredns -n kube-system --type=merge -p "$PATCH_JSON"

echo "Restarting CoreDNS deployment..."
kubectl rollout restart deployment coredns -n kube-system

echo "Waiting for CoreDNS to be ready..."
kubectl rollout status deployment coredns -n kube-system --timeout=120s

echo "CoreDNS configured for sslip.io forwarding"
