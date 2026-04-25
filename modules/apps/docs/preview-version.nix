# Flake app: preview the semantic-release version that would be published
# after merging the current branch into a target branch.
#
#   nix run .#preview-version                         # root package on main
#   nix run .#preview-version -- main packages/docs   # monorepo package preview
#
# Hermetic: semantic-release and its plugins are provided by the
# vanixiets-docs-deps derivation linked into the worktree at runtime; no
# prior `bun install` or pkgs.semantic-release dependency.
#
# Template bifurcation (writeShellApplication): PURE READFILE FORM.
# `text = builtins.readFile ./preview-version.sh` — the sidecar is consumed
# verbatim, no nix-eval-time string interpolation. The only nix-injected
# value is DOCS_NODE_MODULES, exposed via `runtimeEnv` at invocation time.
# Contrast with `deploy.nix`, which uses the interpolation form because it
# must inject the DOCS_PAYLOAD store path into the script preamble.
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
              DOCS_NODE_MODULES = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules";
            };
            text = builtins.readFile ./preview-version.sh;
          }
        );
      };
    };
}
