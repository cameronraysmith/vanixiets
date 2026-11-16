#!/usr/bin/env bash
# shellcheck shell=bash
# Idempotent via grep detection of the existing "sslip.io" block in the Corefile.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-configure-dns [--help]

Patches the kube-system/coredns ConfigMap to add a sslip.io:53 stanza
that answers <name>.<a>.<b>.<c>.<d>.sslip.io (a valid dotted IPv4) with
the A record a.b.c.d in-cluster, forwards every other sslip.io query to
1.1.1.1 and 8.8.8.8, then rolls the coredns Deployment so the new
Corefile takes effect. Idempotent; re-running on an already-patched
cluster is a no-op.

Requires kubectl context pointing at a running k3d cluster with
Cilium (or another CNI) already Ready.
EOF
    exit 0
    ;;
esac

echo "Waiting for CoreDNS to be running..."
kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=120s

echo "Patching CoreDNS ConfigMap to answer sslip.io names in-cluster..."
CURRENT=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}')
if echo "$CURRENT" | grep -q "sslip.io"; then
  echo "CoreDNS already configured for sslip.io"
  exit 0
fi

# Computed in-cluster because resolvers with DNS-rebinding protection strip private-address answers.
SSLIP_BLOCK=$(cat <<'EOF'
sslip.io:53 {
    template IN A sslip.io {
        match "^(?:[^.]+\.)*(?P<a>25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(?P<b>25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(?P<c>25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(?P<d>25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.sslip\.io\.$"
        answer "{{ .Name }} 60 IN A {{ .Group.a }}.{{ .Group.b }}.{{ .Group.c }}.{{ .Group.d }}"
        fallthrough
    }
    forward . 1.1.1.1 8.8.8.8
    cache 30
}
EOF
)
PATCHED="${SSLIP_BLOCK}"$'\n'"${CURRENT}"
PATCH_JSON=$(jq -n --arg corefile "$PATCHED" '{"data": {"Corefile": $corefile}}')
kubectl patch configmap coredns -n kube-system --type=merge -p "$PATCH_JSON"

echo "Restarting CoreDNS deployment..."
kubectl rollout restart deployment coredns -n kube-system

echo "Waiting for CoreDNS to be ready..."
kubectl rollout status deployment coredns -n kube-system --timeout=120s

echo "CoreDNS configured to answer sslip.io names"
