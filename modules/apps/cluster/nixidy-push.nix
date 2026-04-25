# nixidy-push.nix - Rsync rendered manifests to the local-k3d private repo.
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
