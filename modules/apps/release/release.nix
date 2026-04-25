# release.nix - Production semantic-release wrapper as a flake app.
#
#   nix run .#release -- <package-path>
#   nix run .#release -- <package-path> --dry-run
#   nix run .#release -- info <package-path>
#   nix run .#release -- --help
#
# Configures git, invokes semantic-release against the target monorepo
# package, filters `@semantic-release/github` out of the plugin list when
# `--dry-run` is set (so GITHUB_TOKEN is not required for previews), and
# provides an `info` subcommand emitting release info as JSON.
#
# Hermetic: semantic-release and all plugins are provided by the
# vanixiets-docs-deps derivation and linked into the package directory at
# runtime. Callers do not need to run `bun install`.
#
# Expected caller environment (CI-only):
#   GITHUB_TOKEN, CI, RELEASE_REPO_ROOT,
#   GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL,
#   GIT_COMMITTER_NAME / GIT_COMMITTER_EMAIL.
#
# Template bifurcation (writeShellApplication): PURE READFILE FORM.
# `text = builtins.readFile ./release.sh` — the sidecar is consumed verbatim,
# no nix-eval-time string interpolation. The only nix-injected value is
# DOCS_NODE_MODULES, which is provided via `runtimeEnv` (an env var set by
# the writeShellApplication wrapper at invocation time), not via `text`
# interpolation. Contrast with `deploy.nix` (modules/apps/docs/), which uses
# the interpolation form because it must inject derivation outPaths into
# the script preamble.
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
              pkgs.jq
              pkgs.gnugrep
              pkgs.coreutils
              # Explicitly declare every host-PATH binary that release.sh OR
              # any transitive semantic-release plugin / node_modules helper
              # might shell out to. The buildbot-effects bwrap sandbox
              # provides only /nix/store ro-bind + writeShellApplication
              # runtimeInputs PATH (no host PATH binaries); a missing input
              # surfaces only at runtime as `command not found`.
              pkgs.gnused
              pkgs.gawk
              pkgs.findutils
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
