#!/usr/bin/env bash
# shellcheck shell=bash
# Block until every ArgoCD Application is Healthy and Synced, then verify the root Gateway is Programmed by Cilium.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: k3d-wait-argocd-sync [--help]

Waits for the app-of-apps-managed ArgoCD Applications to come online in
the cluster, then gates on each becoming Healthy and Synced, and finally
waits for the main-gateway Gateway to be Programmed by Cilium.

Sync waves (from nixidy local-k3d env):
  Wave -1 (adoption): cilium, argocd, sops-secrets-operator, step-ca
  Wave 0:             cert-manager
  Wave 1-2:           cluster-issuer, gateway, gateway-api
  Wave 3:             argocd-route
EOF
    exit 0
    ;;
esac

echo "=== Waiting for ArgoCD Applications ==="
echo "Applications managed by nixidy sync waves:"
echo "  Wave -1 (adoption): cilium, argocd, sops-secrets-operator, step-ca"
echo "  Wave 0: cert-manager"
echo "  Wave 1-2: cluster-issuer, gateway, gateway-api"
echo "  Wave 3: argocd-route"
echo ""

# All expected applications (app-of-apps creates these asynchronously)
EXPECTED_APPS=(
  apps
  argocd
  argocd-route
  cert-manager
  cilium
  cluster-issuer
  gateway
  gateway-api
  sops-secrets-operator
  step-ca
)

echo "Waiting for all ${#EXPECTED_APPS[@]} applications to exist..."
for app in "${EXPECTED_APPS[@]}"; do
  echo -n "  Waiting for $app... "
  # kubectl wait fails immediately if resource doesn't exist, so poll instead
  timeout 300 bash -c "until kubectl get application/$app -n argocd &>/dev/null; do sleep 2; done"
  echo "exists"
done

echo ""
echo "Waiting for the cilium GatewayClass to be Accepted..."
# The gateway-api app (wave -2) creates the GatewayClass; the cilium operator
# accepts it only if its Gateway API controller started. When it did not, every
# Gateway waits "for controller" until the Healthy waits below time out, so
# fail here with the operator's own reason instead.
timeout 300 bash -c "until kubectl get gatewayclass/cilium &>/dev/null; do sleep 2; done"
if ! kubectl wait --for=condition=Accepted gatewayclass/cilium --timeout=120s; then
  echo "error: GatewayClass cilium not Accepted; cilium-operator Gateway API log:" >&2
  kubectl logs -n kube-system deploy/cilium-operator --tail=2000 | grep -i 'gateway' | grep -iE 'warn|error|requires|not found' >&2 || true
  exit 1
fi

echo ""
echo "Listing applications..."
kubectl get applications -n argocd -o wide || true
echo ""

echo "Waiting for all applications to be Healthy..."
for app in "${EXPECTED_APPS[@]}"; do
  echo -n "  Waiting for $app to be Healthy... "
  kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/"$app" -n argocd --timeout=600s >/dev/null
  echo "done"
done

echo ""
echo "Waiting for all applications to be Synced..."
for app in "${EXPECTED_APPS[@]}"; do
  echo -n "  Waiting for $app to be Synced... "
  kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/"$app" -n argocd --timeout=300s >/dev/null
  echo "done"
done

echo ""
echo "=== Waiting for Gateway to be programmed ==="
# ArgoCD reports Healthy before Cilium fully programs the Gateway
# Wait for the actual Gateway condition, not just ArgoCD's view
kubectl wait --for=condition=Programmed gateway/main-gateway -n gateway-system --timeout=300s

echo ""
echo "=== All ArgoCD applications synced and healthy ==="
kubectl get applications -n argocd -o wide
