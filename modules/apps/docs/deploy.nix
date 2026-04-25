# Deploy the vanixiets-docs derivation to Cloudflare Workers.
#
#   nix run .#deploy-docs -- preview <branch>
#   nix run .#deploy-docs -- production
#
# Why: consumes the nix-built CF Worker payload from
# config.packages.vanixiets-docs (DOCS_PAYLOAD).
#
# Template bifurcation (writeShellApplication): INTERPOLATION FORM.
# `text` is a nix string that injects one eval-time-computed path
# (DOCS_PAYLOAD via config.packages.vanixiets-docs) into the script preamble
# before the readFile'd sidecar body. Contrast with `release.nix` and
# `preview-version.nix`, which use the pure
# `text = builtins.readFile ./<name>.sh` form because they have no
# nix-eval-time path injection requirement (they rely on runtimeEnv only).
{ ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      apps.deploy-docs = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "deploy-docs";
            # Secrets flow via inherited env (never via `sops exec-env`
            # inside the script), so pkgs.sops / pkgs.age are not required
            # runtime inputs.
            #
            # sed/awk/grep/find are explicitly declared because the
            # hercules-ci-effects bwrap sandbox PATH does not include them
            # by default. Required for the writeShellApplication invariant
            # that PATH equals runtimeInputs at runtime.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.jq
              pkgs.coreutils
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.findutils
            ];
            runtimeEnv = {
              DOCS_NODE_MODULES = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules";
            };
            text = ''
              export DOCS_PAYLOAD=${lib.escapeShellArg config.packages.vanixiets-docs}
              ${builtins.readFile ./deploy.sh}
            '';
          }
        );
      };
    };
}
