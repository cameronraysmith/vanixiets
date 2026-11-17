# Gateway API CRDs Application for Phase 4 bootstrap
#
# Adopts the Gateway API CRDs that Phase 3b (kluctl/easykubenix,
# kubernetes/modules/gateway-api) installs in the foundation stage, and adds
# the cilium GatewayClass. ArgoCD takes ownership via ServerSideApply without
# recreating resources.
#
# The CRDs must exist before cilium-operator starts, which is why Phase 3b
# installs them; this wave ordering (-2, before Cilium at -1) cannot do that,
# because the operator is already running when ArgoCD syncs.
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

  # Cilium GatewayClass - required for Cilium Gateway controller to reconcile Gateways
  ciliumGatewayClass = ''
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: cilium
    spec:
      controllerName: io.cilium/gateway-controller
  '';
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

    # Use yamls for raw CRD content (CRDs + GatewayClass)
    yamls = crdYamls ++ [ ciliumGatewayClass ];
  };
}
