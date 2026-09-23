#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-wait-ready [--help]

Blocks until all Phase-3 (foundation + infrastructure) pods are Ready in
the local-k3d cluster, in the order:

  Foundation:      cilium-agent, cilium-operator         (kube-system)
                   then asserts the agent reports KubeProxyReplacement True
  Infrastructure:  argocd deployments, argocd-app-ctrl   (argocd)
                   step-ca statefulset pod               (step-ca)
                   sops-secrets-operator deployments     (sops-secrets-operator)

Each kubectl-wait carries a 300s timeout. Requires kubectl context
pointing at a live k3d cluster with all manifests already applied.
EOF
    exit 0
    ;;
esac

echo "=== Waiting for Foundation (CNI) ==="
echo "Waiting for Cilium Agent..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=cilium-agent -n kube-system --timeout=300s

echo "Waiting for Cilium Operator..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=cilium-operator -n kube-system --timeout=300s

# The cluster runs without kube-proxy, and cilium >= 1.19 enables its Gateway
# API controller only with kube-proxy replacement. Fail here, naming the
# cause, rather than minutes later as a Gateway stuck "Waiting for controller".
echo "Checking Cilium kube-proxy replacement..."
kpr_status=$(kubectl exec -n kube-system ds/cilium -c cilium-agent -- cilium-dbg status | grep '^KubeProxyReplacement:' || true)
echo "  ${kpr_status:-KubeProxyReplacement: <missing>}"
if [[ "$kpr_status" != *"KubeProxyReplacement:"*"True"* ]]; then
  echo "error: Cilium agent does not report KubeProxyReplacement True" >&2
  exit 1
fi

echo ""
echo "=== Waiting for Infrastructure ==="
echo "Waiting for ArgoCD deployments..."
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s

echo "Waiting for ArgoCD Application Controller..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=300s

echo "Waiting for step-ca..."
# Use StatefulSet pod label to exclude Helm test-connection pod (which always fails)
kubectl wait --for=condition=Ready pod -l statefulset.kubernetes.io/pod-name=step-ca-step-certificates-0 -n step-ca --timeout=300s

echo "Waiting for sops-secrets-operator..."
kubectl wait --for=condition=Available deployment --all -n sops-secrets-operator --timeout=300s

echo ""
echo "=== All foundation and infrastructure pods ready ==="
