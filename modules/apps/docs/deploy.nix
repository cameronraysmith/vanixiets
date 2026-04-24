# Deploy the vanixiets-docs derivation to Cloudflare Workers.
#
#   nix run .#deploy-docs -- preview <branch>
#   nix run .#deploy-docs -- production
#
# Consumes the nix-built CF Worker payload from config.packages.vanixiets-docs
# ($out/{dist/,.wrangler/,wrangler.jsonc}) and dispatches to wrangler against
# the inherited environment per the ADR-002 env-var contract; the caller
# supplies CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID via one of
# {sops exec-env, direnv dotenv, GHA step env, M4 effect preamble reading
# HERCULES_CI_SECRETS_JSON}. See deploy.sh header for the full contract.
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
            # Per ADR-002 env-var contract: secrets flow via inherited env
            # (never via `sops exec-env` inside the script), so pkgs.sops /
            # pkgs.age are no longer required runtime inputs.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.jq
              pkgs.coreutils
              pkgs.git
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
