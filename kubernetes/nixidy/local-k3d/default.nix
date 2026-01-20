# nixidy environment for local-k3d cluster
#
# Phase 4 GitOps configuration: ArgoCD Application definitions for adopting
# Phase 3 infrastructure (Cilium, sops-secrets-operator, step-ca, ArgoCD)
# and managing future applications.
#
# Rendered manifests are pushed to a separate private repository per ADR-006:
# https://github.com/cameronraysmith/local-k3d (private)
#
# Workflow: edit Nix here → nixidy build → push to local-k3d repo → ArgoCD syncs
{ lib, ... }:
{
  imports = [
    ./apps
  ];

  nixidy = {
    target = {
      # Separate private repository for rendered manifests (ADR-006)
      repository = "https://github.com/cameronraysmith/local-k3d.git";
      branch = "main";
      # Manifests at repository root
      rootPath = ".";
    };

    # App-of-Apps pattern: single root Application manages all others
    appOfApps = {
      name = "apps";
      namespace = "argocd";
    };

    # Default sync policy for all applications
    defaults = {
      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
      };
    };
  };
}
