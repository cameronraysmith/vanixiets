# nixidy environment for local-k3d cluster
#
# Phase 4 GitOps configuration: ArgoCD Application definitions for adopting
# Phase 3 infrastructure (Cilium, sops-secrets-operator, step-ca, ArgoCD)
# and managing future applications.
#
# Output: ./manifests/local-k3d/ (rendered Application CRs)
{ lib, ... }:
{
  imports = [
    ./apps
  ];

  nixidy = {
    target = {
      # Repository URL for ArgoCD to fetch manifests
      repository = "https://github.com/cameronraysmith/vanixiets.git";
      # TODO: change back to "main" before merging PR
      branch = "nix-50f";
      # Output path relative to repository root
      rootPath = "./manifests/local-k3d";
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
