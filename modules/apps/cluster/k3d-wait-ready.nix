# k3d-wait-ready.nix - Block until kluctl-deployed foundation + infra pods are Ready.
#
# Usage:
#   nix run .#k3d-wait-ready
#
# Template form: pure readFile (no nix-computed variable injection).
# Mirrors the Phase 3 post-deploy gating that sat in the justfile
# `k3d-wait-ready` recipe. All kubectl waits have deterministic timeouts.
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
