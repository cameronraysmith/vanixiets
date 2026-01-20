# Application modules for local-k3d environment
#
# This directory contains nixidy application definitions.
# Phase 4 bootstrap applications (adopting Phase 3 infrastructure) will be
# added in subsequent commits:
# - cilium.nix
# - sops-secrets-operator.nix
# - step-ca.nix
# - argocd.nix (self-management)
#
# Phase 4 native applications (new deployments via ArgoCD) will follow:
# - cert-manager.nix
# - etc.
{ ... }:
{
  imports = [
    # Application modules will be added here
  ];
}
