# Flake app: preview the semantic-release version that would be published after
# merging the current branch into a target branch.
#
# Usage:
#   nix run .#preview-version                         # root package on main
#   nix run .#preview-version -- main packages/docs   # monorepo package preview
#
# Hermetic: semantic-release and its plugins are provided by the
# docs-node-modules derivation (linked into the worktree at runtime); the app
# is self-contained and does not depend on a prior `bun install` or on
# pkgs.semantic-release.
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
      apps.preview-version = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "preview-version";
            runtimeInputs = with pkgs; [
              nodejs-slim
              git
              jq
              gnugrep
              coreutils
            ];
            runtimeEnv = {
              DOCS_NODE_MODULES = "${config.packages.docs-node-modules}/node_modules";
            };
            text = builtins.readFile ./preview-version.sh;
          }
        );
      };
    };
}
