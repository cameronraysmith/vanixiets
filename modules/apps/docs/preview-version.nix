# Flake app: preview the semantic-release version that would be published after
# merging the current branch into a target branch.
#
# Usage:
#   nix run .#preview-version                         # root package on main
#   nix run .#preview-version -- main packages/docs   # monorepo package preview
#
# Replaces the `nix develop -c just preview-version ...` pathway: all runtime
# dependencies (semantic-release, bun, nodejs, git, jq, grep, coreutils) are
# supplied via writeShellApplication's runtimeInputs rather than a devShell
# wrapper.
#
# Platform gate: pkgs.semantic-release declares aarch64-linux as a badPlatforms
# entry, so this app is undefined on that system. `nix eval
# .#apps.aarch64-linux.preview-version` will fail cleanly rather than producing
# a broken wrapper.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    lib.optionalAttrs (system != "aarch64-linux") {
      apps.preview-version = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "preview-version";
            runtimeInputs = with pkgs; [
              semantic-release
              bun
              nodejs_24
              git
              jq
              gnugrep
              coreutils
            ];
            text = builtins.readFile ./preview-version.sh;
          }
        );
      };
    };
}
