# Application modules for local-k3d environment
#
# This directory contains nixidy application definitions.
#
# Phase 4 bootstrap applications adopt Phase 3 infrastructure deployed by
# kluctl/easykubenix. ArgoCD takes ownership via ServerSideApply without
# recreating resources. Helm values must match easykubenix exactly.
#
# Phase 4 native applications (new deployments via ArgoCD) will follow:
# - cert-manager.nix
# - etc.
{ ... }:
{
  imports = [
    # Phase 4 bootstrap: adopt Phase 3 infrastructure
    ./cilium.nix
    ./sops-secrets-operator.nix
    ./step-ca.nix
    ./argocd.nix
  ];
}
