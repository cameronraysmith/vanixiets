# Gateway API CRD module for easykubenix
#
# Installs the standard-channel Gateway API CRDs (and the safe-upgrades
# ValidatingAdmissionPolicy shipped beside them) from the gateway-api-src
# flake input, received via specialArgs.
#
# They belong to the foundation stage, beside Cilium: cilium-operator checks
# for the Gateway API CRDs once, when it starts, and runs its Gateway
# controller only if they are already there. Installed any later (e.g. by the
# nixidy gateway-api Application), the GatewayClass is never Accepted until
# something happens to restart the operator. As CustomResourceDefinitions they
# land in an earlier kluctl barrier than the cilium-operator Deployment.
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

  crdDir = "${gateway-api-src}/config/crd/standard";

  crdFiles =
    let
      yamls = lib.filter (lib.hasSuffix ".yaml") (lib.attrNames (builtins.readDir crdDir));
    in
    lib.throwIf (yamls == [ ])
      "gateway-api: no *.yaml manifests found in ${crdDir}; the upstream CRD layout moved, update kubernetes/modules/gateway-api/default.nix"
      yamls;

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
  };

  config = lib.mkIf cfg.enable {
    importyaml = lib.listToAttrs (
      map (filename: lib.nameValuePair "gateway-api-${filename}" { src = mkCrdDrv filename; }) crdFiles
    );
  };
}
