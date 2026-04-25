# k3d-full.nix - Full local-k3d lifecycle: down -> up -> deploy.
#
# Delegates to the underlying justfile recipes for k3d-down, k3d-up, and
# k3d-deploy. `just` is a runtimeInput because the recipes themselves
# still need k3d/ctlptl/kubectl/etc on PATH; those come from the user's
# dev environment (writeShellApplication prepends runtimeInputs to $PATH
# without stripping it).
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-full = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-full";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.git
              pkgs.just
            ];
            text = builtins.readFile ./k3d-full.sh;
          }
        );
      };
    };
}
