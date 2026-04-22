# nixidy-bootstrap.nix - Apply the local-k3d app-of-apps bootstrap Application CR.
#
# Usage:
#   nix run .#nixidy-bootstrap
#
# Template form: pure readFile (no nix-computed variable injection).
# Emits the bootstrap Application CR to stdout and pipes it into
# `kubectl apply -f -` against the live k3d cluster context.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      apps.nixidy-bootstrap = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nixidy-bootstrap";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.kubectl
              config.packages.nixidy
            ];
            text = builtins.readFile ./nixidy-bootstrap.sh;
          }
        );
      };
    };
}
