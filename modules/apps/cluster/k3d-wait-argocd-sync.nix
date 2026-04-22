# k3d-wait-argocd-sync.nix - Wait for all ArgoCD Applications to reach Synced + Healthy.
#
# Usage:
#   nix run .#k3d-wait-argocd-sync
#
# Template form: pure readFile (no nix-computed variable injection).
# Matches the Phase-4 post-bootstrap gating from the justfile
# `k3d-wait-argocd-sync` recipe. The expected-apps list mirrors the
# nixidy sync-wave declarations and is the source of truth at this layer.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-wait-argocd-sync = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-wait-argocd-sync";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.kubectl
            ];
            text = builtins.readFile ./k3d-wait-argocd-sync.sh;
          }
        );
      };
    };
}
