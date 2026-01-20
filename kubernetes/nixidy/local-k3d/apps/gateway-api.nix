# Gateway API CRDs Application for Phase 4 bootstrap
#
# Adopts existing Gateway API CRDs from Phase 3b (kluctl/easykubenix).
# ArgoCD takes ownership via ServerSideApply without recreating resources.
#
# Gateway API CRDs must be installed before Cilium's gatewayAPI.enabled works.
# Sync wave -2: before Cilium (-1) to ensure CRDs are registered.
{
  lib,
  pkgs,
  gateway-api-src,
  ...
}:
let
  # CRD source paths from gateway-api-src flake input
  crdDir = "${gateway-api-src}/config/crd/standard";

  # Read all YAML files from the standard CRD directory
  crdFiles = lib.pipe (builtins.readDir crdDir) [
    (lib.filterAttrs (_name: type: type == "regular"))
    (lib.filterAttrs (name: _type: lib.hasSuffix ".yaml" name))
    builtins.attrNames
  ];

  # Read CRD file contents as YAML strings
  crdYamls = map (filename: builtins.readFile "${crdDir}/${filename}") crdFiles;
in
{
  applications.gateway-api = {
    # CRDs are cluster-scoped, but Application needs a namespace
    # Use kube-system for infrastructure CRDs
    namespace = "kube-system";

    # Adoption-safe sync options
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
        applyOutOfSyncOnly = true;
        # No namespace creation needed for CRDs
        createNamespace = false;
      };
    };

    # Sync wave -2: CRDs before Cilium (-1)
    annotations."argocd.argoproj.io/sync-wave" = "-2";

    # Use yamls for raw CRD content
    yamls = crdYamls;
  };
}
