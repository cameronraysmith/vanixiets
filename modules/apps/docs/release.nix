# release.nix - Production semantic-release wrapper as a flake app.
#
# Usage:
#   nix run .#release -- <package-path>
#   nix run .#release -- packages/docs
#
# Hermetic: semantic-release and all plugins are provided by the
# vanixiets-docs-deps derivation and linked into the package directory at runtime.
# Callers do not need to run `bun install`.
#
# Expected caller environment (not loaded from sops; CI-only):
#   GITHUB_TOKEN - GitHub authentication for the @semantic-release/github plugin
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
      apps.release = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "release";
            runtimeInputs = [
              pkgs.nodejs-slim
              pkgs.git
            ];
            runtimeEnv = {
              DOCS_NODE_MODULES = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules";
            };
            text = builtins.readFile ./release.sh;
          }
        );
      };
    };
}
