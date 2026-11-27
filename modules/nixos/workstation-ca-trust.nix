# The two private roots a workstation reaches: caddy's root for the .zt
# services behind cinnabar, and the local k8s development CA. Both are read
# from the files stibnite trusts (modules/darwin/fleet-services-trust.nix and
# stibnite's host module), so a rotation reaches every workstation together.
{ config, ... }:
let
  inherit (config.flake.lib) vars;
in
{
  flake.modules.nixos.workstation-ca-trust = {
    security.pki.certificateFiles = [
      # The public file of cinnabar's clan vars generator caddy-root-ca.
      (
        vars.path {
          machine = "cinnabar";
          generator = "caddy-root-ca";
          file = "root.crt";
        }
        + "/value"
      )
      # Public half of the local cluster's step-ca root; the key is sops-encrypted.
      ../../kubernetes/clusters/local/pki/root_ca.crt
    ];
  };
}
