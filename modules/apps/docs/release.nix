# release.nix - Production semantic-release wrapper as a flake app.
#
# Usage:
#   nix run .#release -- <package-path>
#   nix run .#release -- packages/docs
#
# This is a thin nix-wrapped replacement for `just release-package`. It runs
# `bun run release` in the specified package directory with bun, nodejs, and
# git provided on PATH via writeShellApplication; no `nix develop` prefix is
# required.
#
# Expected caller environment (not loaded from sops; CI-only):
#   GITHUB_TOKEN - GitHub authentication for the @semantic-release/github plugin
#
# The caller is responsible for having run `bun install` beforehand so that
# node_modules/ (including semantic-release@25.0.2) is present.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.release = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "release";
            runtimeInputs = [
              pkgs.bun
              pkgs.nodejs_24
              pkgs.git
            ];
            text = builtins.readFile ./release.sh;
          }
        );
      };
    };
}
