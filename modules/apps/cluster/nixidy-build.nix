# nixidy-build.nix - Render nixidy manifests for local-k3d to ./result.
#
# Usage:
#   nix run .#nixidy-build
#
# Template form: pure readFile (no nix-computed variable injection).
# The nixidy CLI is exposed via config.packages.nixidy (set in
# modules/nixidy.nix) and added to runtimeInputs; the flake-app
# invocation resolves the env at `.#local-k3d` using the current
# system's nixidyEnvs.<system>.local-k3d output.
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
      apps.nixidy-build = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nixidy-build";
            runtimeInputs = [
              pkgs.coreutils
              config.packages.nixidy
            ];
            text = builtins.readFile ./nixidy-build.sh;
          }
        );
      };
    };
}
