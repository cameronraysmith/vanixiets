# Producer-path materialization flake-app for the vanixiets apm skills marketplace.
#
# Installs this repo's own 18 apm skill packages back into the repo that
# publishes them, resolved from github `main` rather than the worktree so the
# committed lockfile reproduces in any environment. Mirrors the
# apm-marketplace-validate flake-app + co-located .sh sidecar convention.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    {
      apps.apm-skills-install = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "apm-skills-install";
            runtimeInputs = [
              pkgs.apm
              pkgs.git # repo root resolution
              pkgs.yq-go
              pkgs.coreutils
              pkgs.findutils
            ];
            text = builtins.readFile ./apm-skills-install.sh;
          }
        );
      };
    };
}
