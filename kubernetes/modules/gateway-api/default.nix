# Gateway API CRD module for easykubenix
#
# Installs Gateway API CRDs from kubernetes-sigs/gateway-api.
# Required before Cilium can enable gatewayAPI.enabled = true.
#
# Receives gateway-api-src from flake inputs via specialArgs.
{
  config,
  lib,
  pkgs,
  gateway-api-src,
  ...
}:
let
  moduleName = "gateway-api";
  cfg = config.${moduleName};

  # CRD source paths from gateway-api-src flake input
  crdDir = "${gateway-api-src}/config/crd/standard";

  # Create derivation for each CRD file (required for importyaml)
  # importyaml expects either a derivation or URL, not a store path string
  mkCrdDrv =
    filename:
    pkgs.runCommand "gateway-api-crd-${filename}" { } ''
      cp ${crdDir}/${filename} $out
    '';
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.4.1";
      description = "Gateway API version (must match gateway-api-src flake input)";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Import Gateway API CRDs from source
      # Filter to only .yaml files (excludes any non-CRD files)
      importyaml = lib.pipe (builtins.readDir crdDir) [
        (lib.filterAttrs (_name: type: type == "regular"))
        (lib.filterAttrs (name: _type: lib.hasSuffix ".yaml" name))
        (lib.mapAttrs' (
          filename: _type: {
            name = "gateway-api-${filename}";
            value.src = mkCrdDrv filename;
          }
        ))
      ];
    })

    # API mappings always defined (allows other modules to reference Gateway API types)
    {
      kubernetes.apiMappings = {
        GatewayClass = "gateway.networking.k8s.io/v1";
        Gateway = "gateway.networking.k8s.io/v1";
        HTTPRoute = "gateway.networking.k8s.io/v1";
        GRPCRoute = "gateway.networking.k8s.io/v1";
        ReferenceGrant = "gateway.networking.k8s.io/v1beta1";
        BackendTLSPolicy = "gateway.networking.k8s.io/v1alpha3";
      };
      kubernetes.namespacedMappings = {
        GatewayClass = false;
        Gateway = true;
        HTTPRoute = true;
        GRPCRoute = true;
        ReferenceGrant = true;
        BackendTLSPolicy = true;
      };
    }
  ];
}
