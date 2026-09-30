# Deploy the vanixiets-docs derivation to Cloudflare Workers.
#
#   nix run .#deploy-docs -- production --rev <sha>
#   nix run .#deploy-docs -- preview --rev <sha> --name <name> [--payload <dir>]
#   nix run .#deploy-docs -- versions | deployments [--limit <n>] | tail
#
# nixbot's docs effect also runs the `pull-request` and `pull-request-closed`
# modes, which read the event environment instead of arguments.
#
# Why: the program deploys the nix-built CF Worker payload from
# config.packages.vanixiets-docs, interpolated into the script as the
# non-exported shell variable `builtin_payload` so no environment variable can
# replace what production deploys. Only Previews take another build: through
# --payload, or the store path nixbot built for a pull request.
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
            # The effect sandbox PATH is runtimeInputs only: curl reaches the
            # forge and nixbot's build API, nix provides nix-store to realise
            # a pull request's payload.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.curl
              pkgs.jq
              pkgs.nix
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.findutils
            ];
            runtimeEnv = {
              DOCS_NODE_MODULES = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules";
              DEPLOY_DOCS_CHECK_RUN = config.apps.github-check-run.program;
              DEPLOY_DOCS_PULL_REQUEST = config.apps.github-pull-request.program;
            };
            text = ''
              builtin_payload=${lib.escapeShellArg config.packages.vanixiets-docs}
              ${builtins.readFile ./deploy.sh}
            '';
          }
        );
      };
    };
}
