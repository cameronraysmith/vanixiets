# Regenerate the vendored OpenSpec Claude assets (skills + opsx commands) by
# running the flake-pinned openspec CLI in a sandbox. Mirrors regenerate-bun-nix.
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
              pkgs.bun # provides bunx for the npm-published @fission-ai/openspec
              pkgs.coreutils
              pkgs.fd
              pkgs.ripgrep
              pkgs.gnused
              pkgs.git # repo root via git rev-parse; the asset rewrite targets the worktree
            ];
            runtimeEnv = {
              OPENSPEC_VERSION = inputs'.llm-agents.packages.openspec.version;
            };
            text = builtins.readFile ./openspec-refresh-vendored-artifacts.sh;
          }
        );
      };
    };
}
