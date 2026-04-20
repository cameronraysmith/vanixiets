# Deploy the vanixiets-docs derivation to Cloudflare Workers.
#
#   nix run .#deploy-docs -- preview <branch>
#   nix run .#deploy-docs -- production
#
# Consumes the nix-built CF Worker payload from config.packages.vanixiets-docs
# ($out/{dist/,.wrangler/,wrangler.jsonc}) and dispatches to wrangler via
# sops exec-env for declarative Cloudflare credential access.
{ inputs, ... }:
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
            runtimeInputs = [
              pkgs.wrangler
              pkgs.sops
              pkgs.age
              pkgs.jq
              pkgs.coreutils
              pkgs.git
            ];
            text = ''
              export DOCS_PAYLOAD=${lib.escapeShellArg config.packages.vanixiets-docs}
              export SOPS_SECRETS_FILE=${lib.escapeShellArg "${inputs.self}/secrets/shared.yaml"}
              ${builtins.readFile ./deploy.sh}
            '';
          }
        );
      };
    };
}
