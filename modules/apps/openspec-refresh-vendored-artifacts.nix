# Regenerate the vendored OpenSpec Claude skill assets offline from the
# flake-pinned openspec package in a sandbox. Mirrors regenerate-bun-nix.
#
# nix run .#openspec-refresh-vendored-artifacts
{ ... }:
{
  perSystem =
    {
      inputs',
      pkgs,
      lib,
      ...
    }:
    {
      apps.openspec-refresh-vendored-artifacts = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "openspec-refresh-vendored-artifacts";
            runtimeInputs = [
              inputs'.llm-agents.packages.openspec # the package programs.openspec installs
              pkgs.nodejs # runs generate-skills.mjs against that package
              pkgs.findutils
              pkgs.coreutils
              pkgs.fd
              pkgs.ripgrep
              pkgs.gnused
              pkgs.git # repo root via git rev-parse; the asset rewrite targets the worktree
            ];
            text = builtins.readFile ./openspec-refresh-vendored-artifacts.sh;
          }
        );
      };
    };
}
