# nixidy-sync.nix - Compose nixidy-build then nixidy-push.
#
# Composes nixidy-build and nixidy-push by invoking them sequentially
# via their published bin names (both exposed as runtimeInputs). Running
# the sidecars directly—rather than going through `nix run .#...`—means
# the sync app is self-contained and does not need `nix` on PATH.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # writeShellApplication closures for the two composed apps. These are
      # already referenced by apps.nixidy-build / apps.nixidy-push via
      # lib.getExe; re-declaring the derivations here lets nixidy-sync
      # place both on its own PATH through runtimeInputs, avoiding a
      # dependency on `nix` or `just` being present at runtime.
      nixidyBuild = pkgs.writeShellApplication {
        name = "nixidy-build";
        runtimeInputs = [
          pkgs.coreutils
          config.packages.nixidy
        ];
        text = builtins.readFile ./nixidy-build.sh;
      };
      nixidyPush = pkgs.writeShellApplication {
        name = "nixidy-push";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.rsync
        ];
        text = builtins.readFile ./nixidy-push.sh;
      };
    in
    {
      apps.nixidy-sync = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nixidy-sync";
            runtimeInputs = [
              pkgs.coreutils
              nixidyBuild
              nixidyPush
            ];
            text = builtins.readFile ./nixidy-sync.sh;
          }
        );
      };
    };
}
