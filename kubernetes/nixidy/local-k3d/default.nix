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
#
# CI override: set ARGOCD_REPO_URL=file:///manifests to use local git mount
{ lib, ... }:
let
  # Allow CI to override repository URL (e.g., file:///manifests for local mount)
  repoURLOverride = builtins.getEnv "ARGOCD_REPO_URL";
  defaultRepoURL = "https://github.com/cameronraysmith/local-k3d.git";
in
{
  imports = [
    ./apps
  ];

  nixidy = {
    target = {
      # Separate private repository for rendered manifests (ADR-006)
      # CI can override via ARGOCD_REPO_URL environment variable
      repository = if repoURLOverride != "" then repoURLOverride else defaultRepoURL;
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
