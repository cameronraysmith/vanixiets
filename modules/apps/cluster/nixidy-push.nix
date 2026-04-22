# nixidy-push.nix - Rsync rendered manifests to the local-k3d private repo.
#
# Usage:
#   nix run .#nixidy-push
#
# Template form: pure readFile (no nix-computed variable injection).
# The target repo path is resolved at runtime from the LOCAL_K3D_REPO
# env var (fallback: $HOME/projects/nix-workspace/local-k3d), mirroring
# the justfile `local_k3d_repo` convention.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.nixidy-push = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nixidy-push";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.git
              pkgs.rsync
            ];
            text = builtins.readFile ./nixidy-push.sh;
          }
        );
      };
    };
}
