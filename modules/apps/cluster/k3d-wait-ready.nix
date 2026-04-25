# k3d-wait-ready.nix - Block until kluctl-deployed foundation + infra pods are Ready.
#
# Mirrors the Phase 3 post-deploy gating that sat in the justfile
# `k3d-wait-ready` recipe.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-wait-ready = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-wait-ready";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.kubectl
            ];
            text = builtins.readFile ./k3d-wait-ready.sh;
          }
        );
      };
    };
}
