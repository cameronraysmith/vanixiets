# Application modules for local-k3d environment
#
# This directory contains nixidy application definitions.
#
# Phase 4 bootstrap applications adopt Phase 3 infrastructure deployed by
# kluctl/easykubenix. ArgoCD takes ownership via ServerSideApply without
# recreating resources. Helm values must match easykubenix exactly.
#
# Phase 4 native applications are fresh deployments via ArgoCD (no adoption).
# Sync waves coordinate deployment order: CRDs at -2, Phase 3 at -1, Phase 4 at 0+.
{ ... }:
{
  imports = [
    # Phase 4 bootstrap: adopt Phase 3 infrastructure
    ./gateway-api.nix # sync wave -2 (CRDs before Cilium)
    ./cilium.nix # sync wave -1
    ./sops-secrets-operator.nix # sync wave -1
    ./step-ca.nix # sync wave -1
    ./argocd.nix # sync wave -1

    # Phase 4 native: fresh deployments via ArgoCD
    ./cert-manager.nix # sync wave 0
    ./cluster-issuer.nix # sync wave 1
    ./test-certificate.nix # sync wave 2
  ];
}
