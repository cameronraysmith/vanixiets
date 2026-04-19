# Regenerate workspace-level generated nix files.
#
# nix run .#regenerate-bun-nix
{ ... }:
{
  perSystem =
    {
      inputs',
      pkgs,
      lib,
      config,
      ...
    }:
    {
      apps.regenerate-bun-nix = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "regenerate-bun-nix";
            runtimeInputs = [
              inputs'.bun2nix.packages.default
              pkgs.git
              config.treefmt.build.wrapper
            ];
            text = ''
              repo_root=$(git rev-parse --show-toplevel)
              cd "$repo_root"
              echo "Regenerating bun.nix from bun.lock using pinned bun2nix..."
              bun2nix --lock-file ./bun.lock --output-file ./bun.nix
              echo "Formatting bun.nix with treefmt..."
              treefmt ./bun.nix
              git --no-pager diff --stat -- ./bun.nix || true
            '';
          }
        );
      };
    };
}
